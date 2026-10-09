"""Exercise the shipped shell installer and launcher with offline release fixtures."""

import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


class LauncherUpdateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.prefix = self.root / 'prefix'
        self.app = self.root / "ECNL app's folder"
        self.assets = self.root / 'assets'
        self.assets.mkdir()
        tools = self.root / 'tools'
        tools.mkdir()
        self.env = os.environ.copy()
        self.env.update(PATH=str(tools) + ':' + self.env['PATH'],
                        ECNL_TEST_ASSETS=str(self.assets), ECNL_TEST_INSTALLER=str(ROOT / 'install.sh'),
                        ECNL_TEST_REQUESTS=str(self.root / 'requests'), ECNL_TEST_RUN=str(self.root / 'runs'),
                        ECNL_TEST_TAG='v1.0.1')
        fake_curl = tools / 'curl'
        fake_curl.write_text('''#!/data/data/com.termux/files/usr/bin/python
import os, pathlib, shutil, sys
args=sys.argv[1:]
url=next(arg for arg in args if arg.startswith('https://'))
with open(os.environ['ECNL_TEST_REQUESTS'],'a') as log:
    log.write(url+'\\n')
if os.environ.get('ECNL_TEST_OFFLINE') == '1':
    sys.exit(7)
if url.endswith('/releases/latest'):
    print('https://github.com/samperez10/ecnl-bot/releases/tag/'+os.environ['ECNL_TEST_TAG'],end='')
    sys.exit(0)
out=pathlib.Path(args[args.index('-o')+1])
name=url.rsplit('/',1)[-1]
if name=='install.sh':
    shutil.copyfile(os.environ['ECNL_TEST_INSTALLER'],out)
else:
    tag=url.split('/download/')[1].split('/')[0]
    source=pathlib.Path(os.environ['ECNL_TEST_ASSETS'])/tag/name
    if name=='SHA256SUMS' and os.environ.get('ECNL_TEST_BAD_SUMS')=='1':
        out.write_text('0'*64+'  ecnl-termux-aarch64.tar.gz\\n')
    else:
        shutil.copyfile(source,out)
''')
        fake_curl.chmod(0o755)
        for version in ('1.0.0', '1.0.1', '1.0.9', '1.0.10'):
            self.make_release(version)
        self.install('1.0.0')
        self.config = self.app / 'data/config.json'
        self.config.write_text(json.dumps({'accounts': [{'username': 'saved-user'}], 'license_key': 'test-only'}))
        self.original_data = self.config.read_bytes()

    def make_release(self, version):
        folder = self.assets / ('v' + version)
        folder.mkdir()
        archive_path = folder / 'ecnl-termux-aarch64.tar.gz'
        app = f'''#!/data/data/com.termux/files/usr/bin/bash
set -eu
if [ "${{1:-}}" = --help ] || [ "${{1:-}}" = tui ]; then exit 0; fi
printf '%s\\n' '{version}' "$*" >> "$ECNL_TEST_RUN"
'''.encode()
        with tarfile.open(archive_path, 'w:gz') as archive:
            for name, data, mode in (
                ('ecnl/ecnl-auto-solver', app, 0o755),
                ('ecnl/release.json', json.dumps({'version': version}).encode(), 0o644),
            ):
                entry = tarfile.TarInfo(name)
                entry.size, entry.mode = len(data), mode
                archive.addfile(entry, io.BytesIO(data))
        (folder / 'SHA256SUMS').write_text(hashlib.sha256(archive_path.read_bytes()).hexdigest()
                                          + '  ecnl-termux-aarch64.tar.gz\n')

    def install(self, version, metadata_only=False):
        folder = self.assets / ('v' + version)
        version_args = [] if metadata_only else ['--version', 'v' + version]
        subprocess.run(['bash', str(ROOT / 'install.sh'), *version_args,
                        '--prefix', str(self.prefix), '--install-dir', str(self.app),
                        '--archive', str(folder / 'ecnl-termux-aarch64.tar.gz'),
                        '--checksum', str(folder / 'SHA256SUMS')], env=self.env,
                       check=True, capture_output=True, text=True)

    def launch(self, *arguments):
        result = subprocess.run([str(self.prefix / 'bin/ecnl'), *arguments], env=self.env,
                                capture_output=True, text=True, check=True, timeout=10)
        self.assertEqual(self.config.read_bytes(), self.original_data)
        subprocess.run(['flock', '-n', str(self.app / '.update-lock'), 'true'], check=True)
        return result

    def test_offline_install_reads_archive_version_metadata(self):
        self.install('1.0.9', metadata_only=True)
        self.assertEqual((self.app / 'current/VERSION').read_text().strip(), '1.0.9')

    def test_new_release_installs_without_prompt_and_forwards_arguments(self):
        before = (self.app / 'current').readlink()
        result = self.launch('run', '--task', 'math', '--cycles', '3')
        self.assertIn('Updating ECNL 1.0.0 → 1.0.1', result.stdout)
        self.assertNotIn('[y/N]', result.stdout)
        self.assertNotEqual((self.app / 'current').readlink(), before)
        runs = (self.root / 'runs').read_text()
        self.assertTrue(runs.startswith('1.0.1\n'))
        self.assertIn('run --task math --cycles 3', runs)
        self.assertIn(str(self.config), runs)
        self.assertEqual((self.app / 'current/VERSION').read_text().strip(), '1.0.1')

    def test_same_or_older_release_never_downloads_or_downgrades(self):
        self.install('1.0.1')
        for latest in ('v1.0.1', 'v1.0.0'):
            self.env['ECNL_TEST_TAG'] = latest
            result = self.launch()
            self.assertNotIn('Updating', result.stdout)
        requests = (self.root / 'requests').read_text()
        self.assertNotIn('/download/', requests)
        self.assertEqual((self.app / 'current/VERSION').read_text().strip(), '1.0.1')

    def test_numeric_version_comparison_handles_two_digit_patch(self):
        self.install('1.0.9')
        self.env['ECNL_TEST_TAG'] = 'v1.0.10'
        self.launch()
        self.assertEqual((self.app / 'current/VERSION').read_text().strip(), '1.0.10')

    def test_network_failure_still_launches_installed_app(self):
        self.env['ECNL_TEST_OFFLINE'] = '1'
        self.launch('status')
        self.assertTrue((self.root / 'runs').read_text().startswith('1.0.0\n'))

    def test_checksum_failure_keeps_working_version_and_user_data(self):
        before = (self.app / 'current').readlink()
        self.env['ECNL_TEST_BAD_SUMS'] = '1'
        result = self.launch()
        self.assertIn('Update failed', result.stderr)
        self.assertEqual((self.app / 'current').readlink(), before)
        self.assertTrue((self.root / 'runs').read_text().startswith('1.0.0\n'))

    def test_active_update_lock_launches_current_app_without_a_second_check(self):
        import fcntl
        with (self.app / '.update-lock').open('w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = subprocess.run([str(self.prefix / 'bin/ecnl'), 'status'], env=self.env,
                                    capture_output=True, text=True, check=True, timeout=10)
            self.assertNotIn('Updating', result.stdout)
            self.assertFalse((self.root / 'requests').exists())
            self.assertTrue((self.root / 'runs').read_text().startswith('1.0.0\n'))
        self.launch('status')
        self.assertEqual((self.app / 'current/VERSION').read_text().strip(), '1.0.1')

    def test_uninstall_bypasses_update_check_and_still_requires_confirmation(self):
        result = subprocess.run([str(self.prefix / 'bin/ecnl'), 'uninstall'], env=self.env,
                                input='n\n', capture_output=True, text=True, check=True)
        self.assertIn('cancelled', result.stdout)
        self.assertFalse((self.root / 'requests').exists())
        self.assertTrue(self.app.exists())
