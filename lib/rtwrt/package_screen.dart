import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/config/app_config.dart';
import 'package:luci_mobile/rtwrt/github_release.dart';
import 'package:luci_mobile/rtwrt/package_publish.dart';
import 'package:luci_mobile/rtwrt/result_dialog.dart';
import 'package:luci_mobile/rtwrt/rtwrt_api.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

/// Install and remove packages. A new init script then shows on Services.
class PackageScreen extends ConsumerStatefulWidget {
  const PackageScreen({super.key});

  @override
  ConsumerState<PackageScreen> createState() => _PackageScreenState();
}

class _PackageScreenState extends ConsumerState<PackageScreen> {
  final _name = TextEditingController();
  String _output = 'Installed packages load when you open this page.';
  bool _busy = false;
  bool _force = true;
  List<RouterPackage> _catalog = const [];
  String? _pick;
  String _catalogStatus = 'Loading GitHub software.';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _list();
      _loadCatalog();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  RtwrtApi? _client() {
    final session = ref.read(sessionProvider);
    final api = ref.read(apiServiceProvider);
    if (session == null || api == null) return null;
    return RtwrtApi(api, session);
  }

  Future<void> _run(String script, {String? action}) async {
    final api = _client();
    if (api == null) {
      if (action != null && mounted) {
        await showRtwrtResult(
          context,
          action: action,
          ok: false,
          detail: 'Not connected to the router.',
        );
      }
      return;
    }
    setState(() => _busy = true);
    try {
      final text = await api.shell(script);
      if (!mounted) return;
      final detail = text.trim().isEmpty ? 'Done.' : text.trim();
      setState(() => _output = detail);
      if (action != null) {
        await showRtwrtResult(
          context,
          action: action,
          ok: !_installFailed(detail),
          detail: _installDetail(detail),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final detail = RtwrtApi.explain(e);
      setState(() => _output = detail);
      await showRtwrtResult(
        context,
        action: action ?? 'Software',
        ok: false,
        detail: detail,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadCatalog() async {
    try {
      final json = await GithubReleases.readJson(AppConfig.packagesUrl);
      final list = routerPackagesFrom(json);
      if (!mounted) return;
      setState(() {
        _catalog = list;
        _catalogStatus = list.isEmpty
            ? 'No software is published on GitHub.'
            : '';
        _pick = list.any((pkg) => pkg.name == _pick)
            ? _pick
            : (list.isEmpty ? null : list.first.name);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _catalogStatus = 'Could not load GitHub software. $e');
    }
  }

  RouterPackage? get _selected {
    for (final pkg in _catalog) {
      if (pkg.name == _pick) return pkg;
    }
    return null;
  }

  Future<void> _installGithub() async {
    final pkg = _selected;
    if (pkg == null || !routerPackageUrl.hasMatch(pkg.url)) {
      await showRtwrtResult(
        context,
        action: 'Install',
        ok: false,
        detail: 'Choose a package from GitHub.',
      );
      return;
    }
    final url = pkg.url.replaceAll("'", '');
    final apk = url.endsWith('.apk');
    final path = apk ? '/tmp/rtwrt-package.apk' : '/tmp/rtwrt-package.ipk';
    final install = packageInstallLine(path, apk: apk, force: _force);
    await _run('''
rm -f $path
if command -v curl >/dev/null 2>&1; then
  curl -fL --retry 2 -o $path '$url'
elif command -v wget >/dev/null 2>&1; then
  wget -O $path '$url'
else
  echo NO_DOWNLOAD
  exit 0
fi
echo DOWNLOAD:\$?
$install
echo INSTALL:\$?
''', action: 'Install ${pkg.name}');
  }

  Future<String?> _githubToken({required bool askWhenMissing}) async {
    final saved = await PackagePublisher.readToken();
    if (saved != null && saved.trim().isNotEmpty && !askWhenMissing) {
      return saved.trim();
    }
    if (!mounted) return null;
    final field = TextEditingController();
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('GitHub token'),
        content: TextField(
          controller: field,
          obscureText: true,
          decoration: InputDecoration(
            labelText: 'Token',
            helperText: saved == null || saved.trim().isEmpty
                ? 'Paste a token once. Later uploads go to GitHub by themselves. Skip still installs on the router.'
                : 'A token is already saved. Paste a new one to replace it, or skip.',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(''),
            child: const Text('Skip'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(field.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    field.dispose();
    if (choice == null || choice.isEmpty) {
      final keep = saved?.trim() ?? '';
      return keep.isEmpty ? null : keep;
    }
    await PackagePublisher.saveToken(choice);
    return choice;
  }

  Future<void> _editToken() async {
    final token = await _githubToken(askWhenMissing: true);
    if (!mounted || token == null) return;
    await showRtwrtResult(
      context,
      action: 'GitHub token',
      ok: true,
      detail: 'GitHub token saved on this phone.',
    );
  }

  Future<void> _upload() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['ipk', 'apk'],
    );
    if (!mounted || file == null) return;
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (e) {
      if (!mounted) return;
      await showRtwrtResult(
        context,
        action: 'Upload',
        ok: false,
        detail: 'The phone did not provide the file bytes. $e',
      );
      return;
    }
    if (!mounted) return;
    final rawName = file.name;
    if (bytes.isEmpty) {
      if (!mounted) return;
      await showRtwrtResult(
        context,
        action: 'Upload',
        ok: false,
        detail: 'The phone did not provide the file bytes.',
      );
      return;
    }
    final safe = safePackageFileName(rawName);
    final apk = safe.toLowerCase().endsWith('.apk');
    if (!apk && !safe.toLowerCase().endsWith('.ipk')) {
      if (!mounted) return;
      await showRtwrtResult(
        context,
        action: 'Upload',
        ok: false,
        detail: 'Choose an .ipk or .apk file.',
      );
      return;
    }
    final api = _client();
    if (api == null) {
      if (!mounted) return;
      await showRtwrtResult(
        context,
        action: 'Upload',
        ok: false,
        detail: 'Not connected to the router.',
      );
      return;
    }
    setState(() => _busy = true);
    final path = apk ? '/tmp/rtwrt-upload.apk' : '/tmp/rtwrt-upload.ipk';
    var routerDetail = '';
    var routerOk = false;
    try {
      final copied = await _copyToRouter(api, bytes, path);
      if (!mounted) return;
      if (copied != null) {
        routerDetail = copied;
      } else {
        final text = await api.shell('''
${packageInstallLine(path, apk: apk, force: _force)}
echo INSTALL:\$?
''');
        routerDetail = text.trim().isEmpty ? 'Done.' : text.trim();
        routerOk = !_installFailed(routerDetail);
      }
    } catch (e) {
      routerDetail = RtwrtApi.explain(e);
    }
    if (!mounted) return;
    setState(() => _output = routerDetail);
    final token = await _githubToken(askWhenMissing: false);
    var github = 'GitHub was not updated.';
    var githubOk = false;
    if (token != null) {
      final published = await PackagePublisher.publish(
        token: token,
        fileName: safe,
        bytes: bytes,
      );
      github = published.message;
      githubOk = published.ok;
      if (githubOk && mounted) await _loadCatalog();
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await showRtwrtResult(
      context,
      action: 'Upload ${packageNameFromFile(safe) ?? safe}',
      ok: routerOk && (token == null || githubOk),
      detail: '${_installDetail(routerDetail)}\n\n$github',
    );
    if (mounted) _list();
  }

  Future<String?> _copyToRouter(
    RtwrtApi api,
    Uint8List bytes,
    String path,
  ) async {
    await api.shell('rm -f $path');
    const size = 24 * 1024;
    for (var start = 0; start < bytes.length; start += size) {
      final end = start + size > bytes.length ? bytes.length : start + size;
      final encoded = base64Encode(bytes.sublist(start, end));
      final text = await api.shell(
        "printf '%s' '$encoded' | base64 -d >> $path && echo CHUNK_OK",
      );
      if (!text.contains('CHUNK_OK')) {
        return text.trim().isEmpty ? 'The upload stopped.' : text.trim();
      }
      if (mounted) {
        setState(() {
          _output =
              'Uploading ${(end / 1024).ceil()} / ${(bytes.length / 1024).ceil()} KB';
        });
      }
    }
    return null;
  }

  void _list() {
    _run(r'''
if command -v apk >/dev/null 2>&1; then
  apk list -I
elif command -v opkg >/dev/null 2>&1; then
  opkg list-installed
else
  echo "No package tool found"
fi
''');
  }

  bool _pkgOk(String name) =>
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9._+-]{0,80}$').hasMatch(name);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: LuciAppBar(
        title: 'Software',
        showBack: true,
        actions: [
          IconButton(
            onPressed: _busy ? null : _list,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (_catalog.isEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(_catalogStatus),
                  )
                else
                  DropdownButtonFormField<String>(
                    key: ValueKey('pkg|$_pick'),
                    initialValue: _pick,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'GitHub software',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final pkg in _catalog)
                        DropdownMenuItem(
                          value: pkg.name,
                          child: Text(
                            pkg.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _pick = value),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Force'),
                  subtitle: const Text(
                    'Reinstall, overwrite, and ignore dependency conflicts',
                  ),
                  value: _force,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _force = value),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: _busy || _selected == null
                            ? null
                            : () async {
                                await _installGithub();
                                if (mounted) _list();
                              },
                        child: const Text('Install from GitHub'),
                      ),
                      FilledButton(
                        onPressed: _busy ? null : _upload,
                        child: const Text('Upload and install'),
                      ),
                      TextButton(
                        onPressed: _busy ? null : _editToken,
                        child: const Text('GitHub token'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Package name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                final name = _name.text.trim();
                                if (!_pkgOk(name)) {
                                  await showRtwrtResult(
                                    context,
                                    action: 'Install',
                                    ok: false,
                                    detail: 'Enter a package name.',
                                  );
                                  return;
                                }
                                await _run(
                                  namedPackageInstall(_sh(name), force: _force),
                                  action: 'Install $name',
                                );
                              },
                        child: const Text('Install'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                final name = _name.text.trim();
                                if (!_pkgOk(name)) {
                                  await showRtwrtResult(
                                    context,
                                    action: 'Remove',
                                    ok: false,
                                    detail: 'Enter a package name.',
                                  );
                                  return;
                                }
                                await _run(
                                  'if command -v apk >/dev/null 2>&1; then apk del ${_sh(name)}; '
                                  'else opkg remove ${_sh(name)}; fi',
                                  action: 'Remove $name',
                                );
                              },
                        child: const Text('Remove'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SelectableText(_output),
            ),
          ),
        ],
      ),
    );
  }
}

bool _installFailed(String detail) {
  return detail.contains('NO_DOWNLOAD') ||
      detail.contains('NO_OPKG') ||
      (detail.contains('DOWNLOAD:') && !detail.contains('DOWNLOAD:0')) ||
      (detail.contains('INSTALL:') && !detail.contains('INSTALL:0'));
}

String _installDetail(String detail) {
  if (detail.contains('NO_OPKG')) {
    return 'This router has no opkg tool, so this .ipk cannot be installed.';
  }
  return detail;
}

String _sh(String value) => "'${value.replaceAll("'", "'\\''")}'";
