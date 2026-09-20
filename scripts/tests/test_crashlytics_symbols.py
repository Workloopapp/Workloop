"""Exercise symbol phase path/exit behavior with fake uploaders, never Firebase."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[2] / 'ios/scripts/upload_crashlytics_symbols.sh'


class CrashlyticsSymbolsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='workloop symbols ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = {**os.environ, 'CONFIGURATION': 'Release', 'PLATFORM_NAME': 'iphoneos',
                    'BUILD_DIR': str(self.root / 'build'), 'PODS_ROOT': str(self.root / 'Pods')}

    def uploader(self, root, code=0):
        path = root / 'SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run'
        path.parent.mkdir(parents=True)
        path.write_text(f'#!/bin/sh\necho fake-symbol-upload\nexit {code}\n')

    def run_phase(self):
        return subprocess.run(['/bin/sh', str(SCRIPT)], env=self.env, capture_output=True, text=True)

    def test_flutter_custom_build_directory(self):
        self.uploader(self.root / 'build')
        result = self.run_phase()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), 'fake-symbol-upload')

    def test_xcode_derived_data_layout(self):
        self.env['BUILD_DIR'] = str(self.root / 'DerivedData/Build/Products')
        self.uploader(self.root / 'DerivedData')
        result = self.run_phase()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), 'fake-symbol-upload')

    def test_flutter_archive_uses_resolved_package_directory(self):
        self.env.update(FLUTTER_APPLICATION_PATH=str(self.root / 'app'),
                        FLUTTER_BUILD_DIR='build',
                        BUILD_DIR=str(self.root / 'ArchiveIntermediates/BuildProductsPath'))
        self.uploader(self.root / 'app/build/ios')
        self.assertEqual(self.run_phase().returncode, 0)

    def test_absolute_flutter_build_directory(self):
        self.env['FLUTTER_BUILD_DIR'] = str(self.root / 'custom output')
        self.uploader(self.root / 'custom output/ios')
        self.assertEqual(self.run_phase().returncode, 0)

    def test_debug_and_simulator_skip_without_requiring_symbols(self):
        for config, platform in [('Debug', 'iphoneos'), ('Profile', 'iphonesimulator')]:
            self.env.update(CONFIGURATION=config, PLATFORM_NAME=platform)
            result = self.run_phase()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, '')

    def test_missing_device_release_uploader_fails_visibly(self):
        result = self.run_phase()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('symbol uploader is missing', result.stderr)

    def test_native_validation_failure_is_not_swallowed(self):
        self.uploader(self.root / 'build', code=17)
        self.assertEqual(self.run_phase().returncode, 17)


if __name__ == '__main__':
    unittest.main()
