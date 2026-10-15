"""Filesystem/identity safety checks for the existing-stack runner; no devices."""
import importlib.util
import io
import json
from pathlib import Path
import stat
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('wallet_runner', ROOT / 'tool/run_shared_wallet_qualification.py')
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)


class SnapshotSafetyTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.device = '857A20C2-601C-4864-AFEB-B525D1B5B4D7'
        self.allowed = self.root / 'Library/Developer/CoreSimulator/Devices' / self.device / 'data/Containers/Data/Application'
        self.fixture = self.allowed / 'owned-container/Library/Application Support/aster_full_wallet_qa/original-run'
        self.fixture.mkdir(parents=True)
        (self.fixture / 'fixture.db').write_text('disposable fixture')
        self.output = self.root / 'private-output'
        self.output.mkdir()
        self.args = SimpleNamespace(device=self.device, run_id='verification-run', restore_from='original-run')
        self.container = self.allowed / 'owned-container'
        self.app_container_patch = patch.object(RUNNER, 'app_container', return_value=self.container)
        self.app_container_patch.start()

    def tearDown(self):
        self.app_container_patch.stop()
        self.temporary.cleanup()

    def test_owned_closed_copy_is_private_and_hash_bound(self):
        with patch.object(Path, 'home', return_value=self.root):
            result = RUNNER.preserve({'storage_root': str(self.fixture), 'native_disposed': True}, self.args, self.output)
        copied = self.output / 'private-device-state'
        self.assertTrue(result['nativeClosed'])
        self.assertEqual(result['filesManifestSha256'], RUNNER.tree_digest(copied))
        self.assertEqual(stat.S_IMODE(copied.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE((copied / 'fixture.db').stat().st_mode), 0o600)

    def test_other_device_copy_is_refused(self):
        self.args.device = '00000000-0000-0000-0000-000000000000'
        with patch.object(RUNNER, 'app_container', return_value=self.root / 'other-device'), self.assertRaises(RuntimeError):
            RUNNER.preserve({'storage_root': str(self.fixture), 'native_disposed': True}, self.args, self.output)
        self.assertFalse((self.output / 'private-device-state').exists())

    def test_other_run_copy_is_refused(self):
        self.args.restore_from = 'another-run'
        with patch.object(Path, 'home', return_value=self.root), self.assertRaises(RuntimeError):
            RUNNER.preserve({'storage_root': str(self.fixture), 'native_disposed': True}, self.args, self.output)

    def test_other_app_same_simulator_copy_is_refused(self):
        wrong = self.allowed / 'other-app/aster_full_wallet_qa/original-run'
        wrong.mkdir(parents=True)
        with self.assertRaises(RuntimeError):
            RUNNER.preserve({'storage_root': str(wrong), 'native_disposed': True}, self.args, self.output)

    def test_open_native_owner_cannot_acknowledge_backup(self):
        with self.assertRaises(RuntimeError):
            RUNNER.preserve({'storage_root': str(self.fixture), 'native_disposed': False}, self.args, self.output)

    def test_linked_wallet_snapshot_is_refused(self):
        outside = self.root / 'unrelated-data'
        outside.write_text('not this wallet')
        (self.fixture / 'linked').symlink_to(outside)
        with self.assertRaises(RuntimeError):
            RUNNER.sync_private_tree(self.fixture)

    def test_restore_never_overwrites_existing_wallet(self):
        event = {'storage_root': str(self.fixture), 'storage_run_id': 'original-run'}
        with patch.object(Path, 'home', return_value=self.root), self.assertRaises(RuntimeError):
            RUNNER.restore_fixture(event, self.args, self.fixture)
        self.assertEqual((self.fixture / 'fixture.db').read_text(), 'disposable fixture')

    def restore_event(self):
        target = self.container / 'Documents/aster_full_wallet_qa/original-run'
        target.parent.mkdir(parents=True)
        return {'storage_root': str(target), 'storage_run_id': 'original-run'}

    def test_restore_copy_matches_verified_closed_manifest(self):
        event = self.restore_event()
        expected = RUNNER.tree_digest(self.fixture)
        RUNNER.restore_fixture(event, self.args, self.fixture, expected)
        restored = Path(event['storage_root'])
        self.assertEqual(RUNNER.tree_digest(restored), expected)
        self.assertEqual(stat.S_IMODE((restored / 'fixture.db').stat().st_mode), 0o600)

    def test_restore_rejects_source_changed_since_qualification(self):
        event = self.restore_event()
        expected = RUNNER.tree_digest(self.fixture)
        (self.fixture / 'fixture.db').write_text('changed source')
        with patch.object(RUNNER.shutil, 'copytree') as copy, \
                self.assertRaisesRegex(RuntimeError, 'changed before restore'):
            RUNNER.restore_fixture(event, self.args, self.fixture, expected)
        copy.assert_not_called()
        self.assertFalse(Path(event['storage_root']).exists())

    def test_restore_rejects_copy_corruption_before_acknowledgement(self):
        event = self.restore_event()
        expected = RUNNER.tree_digest(self.fixture)
        actual_copy = RUNNER.shutil.copytree
        def corrupt_copy(source, target, **options):
            actual_copy(source, target, **options)
            (target / 'fixture.db').write_text('corrupted copy')
        with patch.object(RUNNER.shutil, 'copytree', side_effect=corrupt_copy), \
                patch.object(RUNNER, 'write_ack') as acknowledge, \
                self.assertRaisesRegex(RuntimeError, 'differs from verified closed bytes'):
            RUNNER.restore_fixture(event, self.args, self.fixture, expected)
            RUNNER.write_ack('restore-event', {'restore_verified': True})
        acknowledge.assert_not_called()
        self.assertEqual((self.fixture / 'fixture.db').read_text(), 'disposable fixture')

    def test_android_cross_install_restore_is_refused(self):
        self.args.device = 'emulator-5582'
        with self.assertRaises(RuntimeError):
            RUNNER.restore_fixture({'storage_root': '/data/unsafe'}, self.args, self.fixture)

    def test_command_traversal_is_refused(self):
        with self.assertRaises(RuntimeError):
            RUNNER.write_ack('../other-wallet', {})

    def test_backup_parent_directories_are_durable_before_acknowledgement(self):
        order = []
        actual_sync = RUNNER.sync_directory
        def record_sync(path):
            order.append(Path(path))
            actual_sync(path)
        with patch.object(RUNNER, 'sync_directory', side_effect=record_sync):
            backup = RUNNER.preserve(
                {'storage_root': str(self.fixture), 'native_disposed': True}, self.args, self.output)
            self.assertEqual(order[-2:], [self.output, self.output.parent])
            RUNNER.record_preservation(self.output, self.args, backup)
            self.assertEqual(order[-1], self.output)
            self.assertTrue((self.output / 'preservation.json').is_file())

    def test_backup_acknowledgement_waits_for_durable_preservation_receipt(self):
        order = []
        actual_sync = RUNNER.sync_directory
        def record_sync(path):
            order.append(Path(path))
            actual_sync(path)
        def acknowledge(event_id, payload):
            self.assertTrue((self.output / 'preservation.json').is_file())
            self.assertEqual(order[-3:], [self.output, self.output.parent, self.output])
            order.append('acknowledged')
        with patch.object(RUNNER, 'sync_directory', side_effect=record_sync), \
                patch.object(RUNNER, 'write_ack', side_effect=acknowledge):
            RUNNER.preserve_and_ack({'storage_root': str(self.fixture),
                                    'native_disposed': True, 'id': 'owned-event'},
                                   self.args, self.output)
        self.assertEqual(order[-1], 'acknowledged')

    def test_invalid_backup_is_never_acknowledged(self):
        with patch.object(RUNNER, 'preserve', return_value={'status': 'unavailable'}), \
                patch.object(RUNNER, 'write_ack') as acknowledge, self.assertRaises(RuntimeError):
            RUNNER.preserve_and_ack({'id': 'owned-event'}, self.args, self.output)
        acknowledge.assert_not_called()


class DeviceLaunchSafetyTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.evidence = Path(self.temporary.name)
        self.patch = patch.object(RUNNER, 'EVIDENCE', self.evidence)
        self.patch.start()
        self.device = '857A20C2-601C-4864-AFEB-B525D1B5B4D7'
        self.args = SimpleNamespace(device=self.device, run_id='prior-run',
                                    restore_from=None, stage='full')

    def tearDown(self):
        self.patch.stop()
        self.temporary.cleanup()

    def invocation(self, name='prior-run', device=None):
        output = self.evidence / name
        output.mkdir()
        RUNNER.write_durable_json(output / 'invocation.json', {
            'schemaVersion': 1, 'runId': name, 'device': device or self.device,
            'package': RUNNER.PACKAGE, 'stage': 'full', 'storageRunId': name,
        })
        return output

    def ios_backup(self, output):
        snapshot = output / 'private-device-state'
        snapshot.mkdir()
        (snapshot / 'wallet.db').write_text('disposable closed fixture')
        backup = {'status': 'saved', 'nativeClosed': True,
                  'filesManifestSha256': RUNNER.sync_private_tree(snapshot)}
        RUNNER.record_preservation(output, self.args, backup)
        return snapshot

    def test_same_device_concurrent_runner_is_rejected_and_lock_is_released(self):
        with RUNNER.device_lock(self.device):
            with self.assertRaises(RuntimeError):
                with RUNNER.device_lock(self.device):
                    self.fail('Concurrent owner was accepted')
            with RUNNER.device_lock('emulator-5582'):
                pass
        with RUNNER.device_lock(self.device):
            pass

    def test_prior_unbacked_run_blocks_new_launch_before_subprocess(self):
        self.invocation()
        self.args.run_id = 'another-run'
        with patch.object(RUNNER.subprocess, 'Popen') as launch, self.assertRaises(RuntimeError):
            RUNNER.run_qualification(self.args, None)
        launch.assert_not_called()

    def test_prior_closed_backup_allows_launch_even_without_result_report(self):
        output = self.invocation()
        self.ios_backup(output)
        self.assertFalse((output / 'result.json').exists())
        RUNNER.assert_prior_device_preserved(self.device)

    def test_corrupt_or_missing_ios_backup_still_blocks_next_launch(self):
        output = self.invocation()
        snapshot = self.ios_backup(output)
        (snapshot / 'wallet.db').write_text('changed after backup')
        with self.assertRaises(RuntimeError):
            RUNNER.assert_prior_device_preserved(self.device)
        (snapshot / 'wallet.db').unlink()
        with self.assertRaises(RuntimeError):
            RUNNER.assert_prior_device_preserved(self.device)

    def test_android_archive_bytes_and_hash_must_both_match(self):
        self.args.device = 'emulator-5582'
        output = self.invocation(device=self.args.device)
        archive = output / 'private-device-state.tar'
        archive.write_bytes(b'closed archive fixture')
        backup = {'status': 'saved', 'nativeClosed': True, 'bytes': archive.stat().st_size,
                  'sha256': RUNNER.digest(archive)}
        RUNNER.record_preservation(output, self.args, backup)
        RUNNER.assert_prior_device_preserved(self.args.device)
        archive.write_bytes(b'x' * backup['bytes'])
        with self.assertRaises(RuntimeError):
            RUNNER.assert_prior_device_preserved(self.args.device)
        archive.write_bytes(b'x' * (backup['bytes'] + 1))
        with patch.object(RUNNER, 'digest', return_value=backup['sha256']), self.assertRaises(RuntimeError):
            RUNNER.assert_prior_device_preserved(self.args.device)

    def test_durable_invocation_receipt_exists_before_process_can_start(self):
        app = self.evidence / 'app'
        app.mkdir()
        (app / 'config').mkdir()
        (app / 'config/shared-stack.ios.local.json').write_text('{}')
        stack = self.evidence / 'shared-stack'
        (stack / 'artifacts').mkdir(parents=True)
        contract = stack / 'artifacts/public-contract.rgb'
        contract.write_text('public fixture')
        (stack / 'artifacts/consumer-config.json').write_text(json.dumps({
            'environment': 'LOCAL TEST ONLY', 'network': 'regtest', 'evm_chain_id': 42161,
            'asset': {'public_contract': str(contract), 'sha256': RUNNER.digest(contract)},
        }))
        flushed = []
        actual_sync = RUNNER.sync_directory
        def record_sync(path):
            flushed.append(Path(path))
            actual_sync(path)
        def launch(*args, **kwargs):
            output = self.evidence / self.args.run_id
            receipt = json.loads((output / 'invocation.json').read_text())
            self.assertEqual(receipt['device'], self.device)
            self.assertEqual(receipt['storageRunId'], self.args.run_id)
            self.assertEqual(flushed[-1], output)
            raise RuntimeError('No device process started')
        with patch.object(RUNNER, 'ROOT', app), patch.object(RUNNER, 'SHARED', stack), \
                patch.object(RUNNER, 'source_identity', return_value={'commit': 'test-fixture'}), \
                patch.object(RUNNER, 'resolved_sdk_dependency',
                             return_value={'root': str(app / 'actual-sdk-package')}), \
                patch.object(RUNNER, 'sync_directory', side_effect=record_sync), \
                patch.object(RUNNER.urllib.request, 'urlopen',
                             return_value=io.BytesIO(b'{"ready":true,"mutations":false}')), \
                patch.object(RUNNER.subprocess, 'Popen', side_effect=launch), \
                self.assertRaisesRegex(RuntimeError, 'No device process started'):
            RUNNER.run_qualification(self.args, None)

    def test_other_device_receipt_does_not_block_this_device(self):
        self.invocation(device='emulator-5582')
        RUNNER.assert_prior_device_preserved(self.device)

    def test_malformed_invocation_or_preservation_owner_fails_closed(self):
        output = self.invocation()
        self.ios_backup(output)
        proof_path = output / 'preservation.json'
        proof = json.loads(proof_path.read_text())
        proof['device'] = 'emulator-5582'
        proof_path.write_text(json.dumps(proof))
        with self.assertRaises(RuntimeError):
            RUNNER.assert_prior_device_preserved(self.device)
        (output / 'invocation.json').write_text('{partial')
        with self.assertRaises(RuntimeError):
            RUNNER.assert_prior_device_preserved(self.device)

    def test_historical_pre_receipt_report_is_not_reclassified(self):
        output = self.evidence / 'historical-run'
        output.mkdir()
        (output / 'result.json').write_text('{"status":"failed"}')
        RUNNER.assert_prior_device_preserved(self.device)

    def test_qualification_cannot_pass_on_runner_error_or_source_drift(self):
        backup = {'status': 'saved', 'nativeClosed': True}
        self.assertTrue(RUNNER.qualification_passed(0, True, True, backup, None, False))
        self.assertFalse(RUNNER.qualification_passed(0, True, True, backup, 'RuntimeError', False))
        self.assertFalse(RUNNER.qualification_passed(0, True, True, backup, None, True))
        self.assertFalse(RUNNER.qualification_passed(0, True, False, backup, None, False))

    def test_durable_receipt_flushes_file_before_parent_directory(self):
        events = []
        actual_fsync = RUNNER.os.fsync
        actual_directory = RUNNER.sync_directory
        def fsync(descriptor):
            events.append('file-or-directory-fsync')
            actual_fsync(descriptor)
        def directory(path):
            events.append('parent-directory')
            actual_directory(path)
        with patch.object(RUNNER.os, 'fsync', side_effect=fsync), \
                patch.object(RUNNER, 'sync_directory', side_effect=directory):
            RUNNER.write_durable_json(self.evidence / 'receipt.json', {'device': self.device})
        self.assertEqual(events, ['file-or-directory-fsync', 'parent-directory', 'file-or-directory-fsync'])


class MintReconciliationSafetyTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.evidence = Path(self.temporary.name)
        self.patch = patch.object(RUNNER, 'EVIDENCE', self.evidence)
        self.patch.start()
        self.args = SimpleNamespace(device='857A20C2-601C-4864-AFEB-B525D1B5B4D7',
                                    run_id='reconcile-run', restore_from='original-run',
                                    stage='reconcile-mint')
        self.output = self.evidence / 'original-run'
        self.output.mkdir()
        snapshot = self.output / 'private-device-state'
        snapshot.mkdir()
        (snapshot / 'wallet.db').write_text('closed disposable wallet fixture')
        self.sdk = {'ref': 'd' * 40, 'repository': RUNNER.SDK_REPOSITORY,
                    'root': str(self.evidence / 'actual-sdk'), 'packageConfigSha256': 'e' * 64}
        self.app_identity = {'files': {'lib/app.dart': '1' * 64}}
        self.sdk_identity = {'commit': self.sdk['ref'], 'files': {'lib/sdk.dart': '2' * 64}}
        self.asset = 'rgb:canonical-fixture'
        self.pubkey = '02' + '1' * 64
        self.mint_id = 'original-run-app-ios27-3'
        def event(name, **fields):
            return {'event': name, 'run_id': 'original-run', 'role': 'app-ios27', **fields}
        self.report = {
            'schemaVersion': 1, 'status': 'failed', 'stage': 'full',
            'runId': 'original-run', 'device': self.args.device, 'exitCode': 1,
            'runnerError': None, 'appSourceChangedDuringRun': False,
            'sdkSourceChangedDuringRun': False, 'configurationChangedDuringRun': False,
            'appConfigSha256': 'a' * 64, 'appConfigSha256AtEnd': 'a' * 64,
            'consumerConfigSha256': 'b' * 64, 'consumerConfigSha256AtEnd': 'b' * 64,
            'publicContractSha256': 'c' * 64,
            'sdkDependencyBefore': self.sdk.copy(), 'sdkDependencyAfter': self.sdk.copy(),
            'privateFixtureBackup': {'status': 'saved', 'nativeClosed': True,
                                     'filesManifestSha256': RUNNER.tree_digest(snapshot)},
            'events': [
                event('onboarding_passed', node_public_key=self.pubkey),
                event('same_store_bootstrap_passed', node_public_key=self.pubkey),
                event('fund_requested'), event('btc_confirm_requested'),
                event('rgb_setup_bitcoin_balance', settled_sats=0, future_sats=1979573,
                      spendable_sats=1899573, locked_sats=80000, setup_phase='pending'),
                event('bfa_mint_requested', id=self.mint_id, amount_units=5000000,
                      invoice='rgb:public-fixture-invoice'),
                event('test_failed', code='qa_private_field_rejected', diagnostics=[],
                      sensitive_screen_active=False),
                event('test_cleanup', native_disposed=True),
                event('fixture_backup_verified'),
            ],
        }
        self.acknowledgement = {
            'ok': True, 'id': self.mint_id, 'role': 'app-ios27', 'event': 'bfa_mint_requested',
            'localTestOnly': True, 'amount_units': '5000000', 'asset_id': self.asset,
            'evm_chain_id': 42161, 'receiverBalanceVerified': False,
            'mint': {'amount': '5000000', 'tokenCommission': '0',
                     'invoice': 'rgb:public-fixture-invoice',
                     'phase': 'backend_completed_receiver_unverified'},
        }
        (self.output / 'source-before.json').write_text(json.dumps({
            'app': self.app_identity, 'sdk': self.sdk_identity, 'sdkDependency': self.sdk,
            'appConfigSha256': 'a' * 64, 'consumerConfigSha256': 'b' * 64,
        }))
        (self.evidence / 'commands').mkdir()
        self.ack_path = self.evidence / 'commands' / (self.mint_id + '.json')
        self.save()

    def tearDown(self):
        self.patch.stop()
        self.temporary.cleanup()

    def save(self):
        (self.output / 'result.json').write_text(json.dumps(self.report))
        self.ack_path.write_text(json.dumps(self.acknowledgement))

    def validate(self):
        return RUNNER.mint_reconciliation_source(self.args, 'a' * 64, 'b' * 64,
                                                'c' * 64, self.asset, self.sdk,
                                                self.app_identity, self.sdk_identity)

    def test_known_closed_post_mint_failure_yields_public_checkpoint_without_replay(self):
        before_report = (self.output / 'result.json').read_bytes()
        before_ack = self.ack_path.read_bytes()
        with patch.object(RUNNER.subprocess, 'Popen') as launch, \
                patch.object(RUNNER.urllib.request, 'urlopen') as request:
            _, expected, proof = self.validate()
        launch.assert_not_called()
        request.assert_not_called()
        self.assertEqual(expected, {'node_public_key': self.pubkey, 'btc_future_sats': 1979573,
                                    'btc_spendable_sats': 1899573, 'bfa_settled_units': 5000000,
                                    'bfa_spendable_units': 5000000})
        self.assertFalse(proof['hostVerifiedReceiverBalance'])
        self.assertEqual(proof['sourceReportSha256'], RUNNER.digest(self.output / 'result.json'))
        self.assertEqual(proof['mintAcknowledgementSha256'], RUNNER.digest(self.ack_path))
        self.assertEqual(proof['sourceManifestSha256'], RUNNER.digest(self.output / 'source-before.json'))
        self.assertEqual((self.output / 'result.json').read_bytes(), before_report)
        self.assertEqual(self.ack_path.read_bytes(), before_ack)

    def test_another_failure_or_mutating_followup_is_not_admitted(self):
        self.report['events'][6]['code'] = 'qa_wallet_state_timeout'
        self.save()
        with self.assertRaisesRegex(RuntimeError, 'known public-field harness failure'):
            self.validate()
        self.report['events'][6]['code'] = 'qa_private_field_rejected'
        self.report['events'].append({'event': 'bfa_burn_requested', 'run_id': 'original-run',
                                     'role': 'app-ios27'})
        self.save()
        with self.assertRaisesRegex(RuntimeError, 'additional or uncertain'):
            self.validate()

    def test_android_confirmed_checkpoint_requires_its_hash_bound_closed_archive(self):
        self.args.device = 'emulator-5582'
        self.report['device'] = self.args.device
        for event in self.report['events']:
            event['role'] = 'app-android17'
        self.mint_id = 'original-run-app-android17-3'
        self.report['events'][5]['id'] = self.mint_id
        self.report['events'][4]['setup_phase'] = 'ready'
        self.report['events'][4]['settled_sats'] = 1979573
        archive = self.output / 'private-device-state.tar'
        archive.write_bytes(b'disposable retained Android snapshot')
        self.report['privateFixtureBackup'] = {
            'status': 'saved', 'nativeClosed': True,
            'bytes': archive.stat().st_size, 'sha256': RUNNER.digest(archive),
        }
        self.acknowledgement.update(id=self.mint_id, role='app-android17')
        self.ack_path = self.evidence / 'commands' / (self.mint_id + '.json')
        self.save()
        _, expected, _ = self.validate()
        self.assertEqual(expected['btc_future_sats'], 1979573)
        archive.write_bytes(b'changed archive')
        with self.assertRaisesRegex(RuntimeError, 'Android snapshot hash or size differs'):
            self.validate()

    def test_second_mint_is_refused_even_with_the_original_successful_ack(self):
        self.report['events'].append(self.report['events'][5].copy())
        self.save()
        with self.assertRaisesRegex(RuntimeError, 'exactly one bfa_mint_requested'):
            self.validate()

    def test_wrong_device_configuration_or_changed_sdk_is_refused(self):
        original = json.loads(json.dumps(self.report))
        for key, value in [('device', 'emulator-5582'), ('appConfigSha256', '0' * 64),
                           ('consumerConfigSha256AtEnd', '0' * 64),
                           ('publicContractSha256', '0' * 64), ('sdkSourceChangedDuringRun', True)]:
            with self.subTest(key=key):
                self.report = json.loads(json.dumps(original))
                self.report[key] = value
                self.save()
                with self.assertRaisesRegex(RuntimeError, 'identity or configuration'):
                    self.validate()
        self.report = original
        self.sdk = {**self.sdk, 'ref': 'f' * 40}
        self.save()
        with self.assertRaisesRegex(RuntimeError, 'identity or configuration'):
            self.validate()

    def test_corrupted_closed_wallet_bytes_block_reconciliation(self):
        (self.output / 'private-device-state/wallet.db').write_text('changed after closure')
        with self.assertRaisesRegex(RuntimeError, 'snapshot content hash differs'):
            self.validate()

    def test_only_exact_recovery_harness_and_documentation_changes_are_admitted(self):
        self.app_identity['files']['integration_test/full_wallet_flow_test.dart'] = '3' * 64
        _, _, proof = self.validate()
        self.assertEqual(proof['permittedSourceChanges'], ['integration_test/full_wallet_flow_test.dart'])
        self.app_identity['files']['lib/app.dart'] = '4' * 64
        with self.assertRaisesRegex(RuntimeError, 'Production app or build source changed'):
            self.validate()

    def test_original_sdk_source_bytes_are_bound_independently_of_locked_ref(self):
        self.sdk_identity['files']['lib/sdk.dart'] = '4' * 64
        with self.assertRaisesRegex(RuntimeError, 'original source manifest or SDK differs'):
            self.validate()

    def test_acknowledgement_invoice_and_backend_phase_must_match_the_original_request(self):
        self.acknowledgement['mint']['invoice'] = 'rgb:another-wallet-invoice'
        self.save()
        with self.assertRaisesRegex(RuntimeError, 'mint acknowledgement differs'):
            self.validate()
        self.acknowledgement['mint']['invoice'] = 'rgb:public-fixture-invoice'
        self.acknowledgement['mint']['phase'] = 'not_completed'
        self.save()
        with self.assertRaisesRegex(RuntimeError, 'mint acknowledgement differs'):
            self.validate()

    def test_missing_or_untrusted_mint_ack_never_authorizes_reconciliation(self):
        original = self.acknowledgement.copy()
        for key, value in [('ok', False), ('amount_units', 5000000), ('amount_units', '05000000'),
                           ('asset_id', 'rgb:another'), ('evm_chain_id', 31337),
                           ('role', 'sdk-ios27'), ('receiverBalanceVerified', True)]:
            with self.subTest(key=key, value=value):
                self.acknowledgement = {**original, key: value}
                self.save()
                with self.assertRaisesRegex(RuntimeError, 'mint acknowledgement differs'):
                    self.validate()
        self.ack_path.unlink()
        with self.assertRaises(FileNotFoundError):
            self.validate()

    def test_original_pubkey_and_bitcoin_checkpoint_must_match(self):
        self.report['events'][1]['node_public_key'] = '03' + '2' * 64
        self.save()
        with self.assertRaisesRegex(RuntimeError, 'original wallet identity differs'):
            self.validate()
        self.report['events'][1]['node_public_key'] = self.pubkey
        self.report['events'][4]['spendable_sats'] += 1
        self.save()
        with self.assertRaisesRegex(RuntimeError, 'Bitcoin checkpoint is malformed'):
            self.validate()

    def test_normal_restore_still_rejects_this_failed_full_run(self):
        self.args.stage = 'restore'
        with patch.object(RUNNER.subprocess, 'Popen') as launch, \
                self.assertRaisesRegex(RuntimeError, 'successfully closed and qualified'):
            RUNNER.run_qualification(self.args, None)
        launch.assert_not_called()


class RestorePairSafetyTests(unittest.TestCase):
    def setUp(self):
        first = {'wallet_id': 'a' * 32, 'node_public_key': '02' + '1' * 64,
                 'btc_settled_sats': 100, 'btc_future_sats': 120, 'btc_spendable_sats': 80,
                 'bfa_settled_units': 50, 'bfa_future_units': 50, 'bfa_spendable_units': 40}
        second = {**first, 'wallet_id': 'b' * 32, 'node_public_key': '03' + '2' * 64,
                  'btc_settled_sats': 200, 'btc_future_sats': 200, 'btc_spendable_sats': 150,
                  'bfa_settled_units': 60, 'bfa_future_units': 60, 'bfa_spendable_units': 60}
        self.passed = {key: value for key, value in first.items() if key != 'wallet_id'}
        self.passed.update(event='test_passed', stage='full',
                           wallet_pair={'active_wallet_id': first['wallet_id'],
                                        'profiles': [first, second]})

    def test_both_independent_profiles_and_all_balance_dimensions_are_retained(self):
        pair = RUNNER.restore_pair_checkpoint(self.passed)
        self.assertEqual([profile['wallet_id'] for profile in pair['profiles']], ['a' * 32, 'b' * 32])
        self.assertEqual(pair['profiles'][1]['bfa_spendable_units'], 60)

    def test_second_profile_can_be_the_retained_active_selection(self):
        pair = self.passed['wallet_pair']
        second = pair['profiles'][1]
        pair['active_wallet_id'] = second['wallet_id']
        self.passed.update({key: value for key, value in second.items() if key != 'wallet_id'})
        self.assertEqual(RUNNER.restore_pair_checkpoint(self.passed)['active_wallet_id'], 'b' * 32)

    def test_missing_second_profile_is_never_treated_as_complete_restore(self):
        self.passed['wallet_pair']['profiles'].pop()
        with self.assertRaisesRegex(RuntimeError, 'both retained profile checkpoints'):
            RUNNER.restore_pair_checkpoint(self.passed)

    def test_duplicate_wallet_or_node_identity_is_rejected(self):
        pair = self.passed['wallet_pair']
        pair['profiles'][1]['wallet_id'] = 'a' * 32
        with self.assertRaisesRegex(RuntimeError, 'pair identities'):
            RUNNER.restore_pair_checkpoint(self.passed)
        pair['profiles'][1]['wallet_id'] = 'b' * 32
        pair['profiles'][1]['node_public_key'] = pair['profiles'][0]['node_public_key']
        with self.assertRaisesRegex(RuntimeError, 'pair identities'):
            RUNNER.restore_pair_checkpoint(self.passed)

    def test_secondary_amounts_require_nonnegative_native_integers(self):
        second = self.passed['wallet_pair']['profiles'][1]
        for value in ('60', True, 60.0, -1, 0x8000000000000000):
            with self.subTest(value=value):
                second['bfa_spendable_units'] = value
                with self.assertRaisesRegex(RuntimeError, 'checkpoint is malformed'):
                    RUNNER.restore_pair_checkpoint(self.passed)

    def test_cannot_hide_a_changed_secondary_balance_in_extra_metadata(self):
        self.passed['wallet_pair']['profiles'][1]['event'] = 'test_passed'
        with self.assertRaisesRegex(RuntimeError, 'checkpoint is malformed'):
            RUNNER.restore_pair_checkpoint(self.passed)

    def test_stale_final_active_snapshot_is_rejected(self):
        self.passed['bfa_spendable_units'] -= 1
        with self.assertRaisesRegex(RuntimeError, 'Final active snapshot differs'):
            RUNNER.restore_pair_checkpoint(self.passed)

    def test_root_boolean_amount_cannot_alias_a_valid_zero_integer(self):
        self.passed['wallet_pair']['profiles'][0]['btc_settled_sats'] = 0
        self.passed['btc_settled_sats'] = False
        with self.assertRaisesRegex(RuntimeError, 'Final active snapshot differs'):
            RUNNER.restore_pair_checkpoint(self.passed)

    def test_unknown_active_selection_and_noncanonical_profile_order_are_rejected(self):
        pair = self.passed['wallet_pair']
        pair['active_wallet_id'] = 'c' * 32
        with self.assertRaisesRegex(RuntimeError, 'pair identities'):
            RUNNER.restore_pair_checkpoint(self.passed)
        pair['active_wallet_id'] = 'a' * 32
        pair['profiles'].reverse()
        with self.assertRaisesRegex(RuntimeError, 'pair identities'):
            RUNNER.restore_pair_checkpoint(self.passed)

    def test_bitcoin_total_and_rgb_settled_invariants_remain_distinct(self):
        second = self.passed['wallet_pair']['profiles'][1]
        second['bfa_future_units'] = 40
        RUNNER.restore_pair_checkpoint(self.passed)
        second['btc_spendable_sats'] = 201
        with self.assertRaisesRegex(RuntimeError, 'checkpoint is malformed'):
            RUNNER.restore_pair_checkpoint(self.passed)


class ColdRestoreEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.evidence_root = Path(self.temporary.name)
        self.evidence_patch = patch.object(RUNNER, 'EVIDENCE', self.evidence_root)
        self.evidence_patch.start()
        self.output = self.evidence_root / 'original-full-run'
        self.output.mkdir()
        (self.output / 'result.json').write_text('{"status":"passed"}')
        (self.output / 'source-before.json').write_text('{"app":"public-fixture"}')

    def tearDown(self):
        self.evidence_patch.stop()
        self.temporary.cleanup()

    def evidence(self, android=False):
        if android:
            archive = self.output / 'private-device-state.tar'
            archive.write_bytes(b'closed disposable archive')
            backup = {'status': 'saved', 'nativeClosed': True,
                      'sha256': RUNNER.digest(archive), 'bytes': archive.stat().st_size}
        else:
            snapshot = self.output / 'private-device-state'
            snapshot.mkdir()
            (snapshot / 'wallet.db').write_text('closed disposable wallet')
            backup = {'status': 'saved', 'nativeClosed': True,
                      'filesManifestSha256': RUNNER.tree_digest(snapshot)}
        device = 'emulator-5582' if android else '857A20C2-601C-4864-AFEB-B525D1B5B4D7'
        RUNNER.verify_closed_backup(self.output, device, backup)
        return device, {'sourceRunId': self.output.name,
                        'sourceReportSha256': RUNNER.digest(self.output / 'result.json'),
                        'sourceManifestSha256': RUNNER.digest(self.output / 'source-before.json'),
                        'sourceBackup': backup}

    def test_unchanged_original_closed_ios_bytes_remain_qualified(self):
        device, evidence = self.evidence()
        self.assertFalse(RUNNER.restore_evidence_changed(evidence, device))

    def test_original_ios_database_drift_fails_otherwise_successful_cold_restore(self):
        device, evidence = self.evidence()
        original_report = (self.output / 'result.json').read_bytes()
        original_manifest = (self.output / 'source-before.json').read_bytes()
        (self.output / 'private-device-state/wallet.db').write_text('changed after restore admission')
        changed = RUNNER.restore_evidence_changed(evidence, device)
        self.assertTrue(changed)
        self.assertFalse(RUNNER.qualification_passed(0, True, True, evidence['sourceBackup'], None, changed))
        self.assertEqual((self.output / 'result.json').read_bytes(), original_report)
        self.assertEqual((self.output / 'source-before.json').read_bytes(), original_manifest)

    def test_same_size_android_archive_drift_is_detected_after_admission(self):
        device, evidence = self.evidence(android=True)
        self.assertFalse(RUNNER.restore_evidence_changed(evidence, device))
        archive = self.output / 'private-device-state.tar'
        archive.write_bytes(b'x' * archive.stat().st_size)
        self.assertTrue(RUNNER.restore_evidence_changed(evidence, device))

    def test_android_archive_size_change_is_detected_even_if_digest_matches(self):
        device, evidence = self.evidence(android=True)
        (self.output / 'private-device-state.tar').write_bytes(b'x')
        with patch.object(RUNNER, 'digest', side_effect=lambda path: (
                evidence['sourceBackup']['sha256'] if path.name.endswith('.tar') else
                evidence['sourceReportSha256'] if path.name == 'result.json' else
                evidence['sourceManifestSha256'])):
            self.assertTrue(RUNNER.restore_evidence_changed(evidence, device))

    def test_missing_or_linked_original_backup_is_reported_as_evidence_drift(self):
        device, evidence = self.evidence()
        snapshot = self.output / 'private-device-state'
        renamed = self.output / 'moved-closed-snapshot'
        snapshot.rename(renamed)
        self.assertTrue(RUNNER.restore_evidence_changed(evidence, device))
        snapshot.symlink_to(renamed, target_is_directory=True)
        self.assertTrue(RUNNER.restore_evidence_changed(evidence, device))

    def test_missing_or_linked_original_report_never_crashes_final_reporting(self):
        device, evidence = self.evidence()
        report = self.output / 'result.json'
        original = report.read_bytes()
        report.unlink()
        self.assertTrue(RUNNER.restore_evidence_changed(evidence, device))
        target = self.output / 'same-report-bytes.json'
        target.write_bytes(original)
        report.symlink_to(target)
        self.assertTrue(RUNNER.restore_evidence_changed(evidence, device))


class TransferReconciliationSafetyTests(unittest.TestCase):
    """Synthetic closed G fixtures, with no devices, services or real wallets."""
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.evidence = Path(self.temporary.name)
        self.patch = patch.object(RUNNER, 'EVIDENCE', self.evidence)
        self.patch.start()
        self.run = RUNNER.TRANSFER_RECONCILIATION_RUN
        self.args = SimpleNamespace(device='857A20C2-601C-4864-AFEB-B525D1B5B4D7',
                                    run_id='transfer-reconciliation', restore_from=self.run,
                                    stage='reconcile-transfer')
        self.output = self.evidence / self.run
        self.output.mkdir()
        snapshot = self.output / 'private-device-state'
        metadata = snapshot / 'metadata'
        metadata.mkdir(parents=True)
        self.profile_ids = ['a' * 32, 'b' * 32]
        document = json.dumps({'version': 1, 'activeWalletId': self.profile_ids[1], 'profiles': [
            {'id': value, 'state': 'ready', 'environment': 'regtest'} for value in self.profile_ids]})
        (metadata / 'wallet_registry.a.json').write_text(json.dumps({
            'schema': 1, 'generation': 1, 'document': document,
            'checksum': RUNNER.hashlib.sha256(('1\n1\n' + document).encode()).hexdigest(),
        }))
        self.backup = {'status': 'saved', 'nativeClosed': True,
                       'filesManifestSha256': RUNNER.tree_digest(snapshot)}
        self.sdk = {'ref': 'd' * 40, 'repository': RUNNER.SDK_REPOSITORY,
                    'root': str(self.evidence / 'actual-sdk'), 'packageConfigSha256': 'e' * 64}
        self.app_identity = {'files': {'lib/app.dart': '1' * 64}}
        self.sdk_identity = {'commit': self.sdk['ref'], 'files': {'lib/sdk.dart': '2' * 64}}
        self.asset = 'rgb:canonical-fixture'
        self.original_key, self.imported_key = '02' + '1' * 64, '03' + '2' * 64
        self.txid = '3' * 64
        self.ids = [self.run + '-app-ios27-' + str(i) for i in range(1, 6)]
        def event(name, **fields):
            return {'event': name, 'run_id': self.run, 'role': 'app-ios27', **fields}
        self.events = [
            event('onboarding_passed', node_public_key=self.original_key),
            event('same_store_bootstrap_passed', node_public_key=self.original_key),
            event('fund_requested', id=self.ids[0], address='public-address-a', amount_sats=2000000),
            event('send_ui_confirm_requested', target='bitcoin-onchain', amount_units=20000),
            event('send_ui_accepted', target='bitcoin-onchain', amount_units=20000, txid='4' * 64),
            event('btc_confirm_requested', id=self.ids[1], txid='4' * 64,
                  recipient='public-recipient', amount_sats=20000),
            event('bfa_mint_requested', id=self.ids[2], amount_units=5000000, invoice='public-mint-invoice'),
            event('bfa_receive_passed', node_public_key=self.original_key,
                  bfa_settled_units=5000000, bfa_future_units=5000000, bfa_spendable_units=5000000),
            event('import_passed', node_public_key=self.imported_key, btc_settled_sats=0,
                  btc_spendable_sats=0, bfa_settled_units=0, bfa_future_units=0, bfa_spendable_units=0),
            event('fund_requested', id=self.ids[3], address='public-address-b', amount_sats=2000000),
            event('imported_receive_prepared', invoice='public-blind-invoice', amount_units=1000000,
                  invoice_amount_bound=False),
            event('send_ui_confirm_requested', target='usdt-onchain', amount_units=1000000),
            event('send_ui_accepted', target='usdt-onchain', amount_units=1000000, txid=self.txid),
            event('bfa_transfer_submitted', amount_units=1000000, txid=self.txid),
            event('test_failed', code='qa_import_wallet_state_timeout', diagnostics=[], sensitive_screen_active=False),
            event('test_cleanup', native_disposed=True),
            event('fixture_backup_requested', id=self.ids[4], native_disposed=True, stage='full'),
            event('fixture_backup_verified'),
        ]
        self.report = {
            'schemaVersion': 1, 'status': 'failed', 'stage': 'full', 'runId': self.run,
            'device': self.args.device, 'exitCode': 1, 'runnerError': None,
            'appSourceChangedDuringRun': False, 'sdkSourceChangedDuringRun': False,
            'configurationChangedDuringRun': False, 'appConfigSha256': 'a' * 64,
            'appConfigSha256AtEnd': 'a' * 64, 'consumerConfigSha256': 'b' * 64,
            'consumerConfigSha256AtEnd': 'b' * 64, 'publicContractSha256': 'c' * 64,
            'sdkDependencyBefore': self.sdk.copy(), 'sdkDependencyAfter': self.sdk.copy(),
            'privateFixtureBackup': {'status': 'unavailable'}, 'events': self.events[:11],
        }
        (self.output / 'flutter.log').write_text('public driver failure fixture')
        self.report['flutterLogSha256'] = RUNNER.digest(self.output / 'flutter.log')
        (self.output / 'source-before.json').write_text(json.dumps({
            'app': self.app_identity, 'sdk': self.sdk_identity, 'sdkDependency': self.sdk,
            'appConfigSha256': 'a' * 64, 'consumerConfigSha256': 'b' * 64,
        }))
        (self.output / 'invocation.json').write_text(json.dumps({
            'schemaVersion': 1, 'runId': self.run, 'device': self.args.device,
            'package': RUNNER.PACKAGE, 'stage': 'full', 'storageRunId': self.run,
        }))
        (self.output / 'preservation.json').write_text(json.dumps({
            'schemaVersion': 1, 'runId': self.run, 'device': self.args.device,
            'package': RUNNER.PACKAGE, 'storageRunId': self.run, 'backup': self.backup,
        }))
        commands = self.evidence / 'commands'
        commands.mkdir()
        self.acks = {}
        for request in [self.events[i] for i in (2, 5, 6, 9, 16)]:
            ack = {**request, 'ok': True}
            if request['event'] in ('fund_requested', 'btc_confirm_requested'):
                ack['confirmed'] = True
                if request['event'] == 'fund_requested':
                    ack['txid'] = ('5' if request['id'] == self.ids[0] else '6') * 64
            elif request['event'] == 'bfa_mint_requested':
                ack.update(amount_units='5000000', asset_id=self.asset, localTestOnly=True,
                           evm_chain_id=42161, receiverBalanceVerified=False,
                           mint={'amount': '5000000', 'invoice': request['invoice'],
                                 'phase': 'backend_completed_receiver_unverified'})
            else:
                ack = {'ok': True, 'backup_verified': True}
            self.acks[request['id']] = ack
        self.save()
        self.late_sha_patch = patch.object(RUNNER, 'TRANSFER_RECONCILIATION_EVENTS_SHA256',
                                           RUNNER.digest(self.output / 'late-events.json'))
        self.late_sha_patch.start()

    def tearDown(self):
        self.late_sha_patch.stop()
        self.patch.stop()
        self.temporary.cleanup()

    def save(self):
        (self.output / 'result.json').write_text(json.dumps(self.report))
        (self.output / 'late-events.json').write_text(json.dumps(self.events))
        (self.evidence / 'events.jsonl').write_text(''.join(json.dumps(event) + '\n' for event in self.events))
        (self.output / 'late-preservation.json').write_text(json.dumps({
            'schemaVersion': 1, 'sourceReportSha256': RUNNER.digest(self.output / 'result.json'),
            'sourceReportPreserved': True, 'backup': self.backup, 'requestId': self.ids[4],
            'nativeClosed': True, 'financialRequestsSent': 0,
        }))
        for request_id, value in self.acks.items():
            (self.evidence / 'commands' / (request_id + '.json')).write_text(json.dumps(value))

    def validate(self):
        return RUNNER.transfer_reconciliation_source(self.args, 'a' * 64, 'b' * 64,
                                                    'c' * 64, self.asset, self.sdk,
                                                    self.app_identity, self.sdk_identity)

    def test_closed_late_transfer_is_bound_without_rewriting_failed_report_or_replaying(self):
        original = (self.output / 'result.json').read_bytes()
        with patch.object(RUNNER.subprocess, 'Popen') as launch, \
                patch.object(RUNNER.urllib.request, 'urlopen') as request:
            admitted, expected, proof = self.validate()
        launch.assert_not_called()
        request.assert_not_called()
        self.assertEqual(expected['txid'], self.txid)
        self.assertEqual(expected['profile_ids'], self.profile_ids)
        self.assertEqual(expected['original_units'] + expected['imported_units'], 5000000)
        self.assertEqual(admitted['status'], 'failed')
        self.assertTrue(admitted['privateFixtureBackup']['nativeClosed'])
        self.assertEqual((self.output / 'result.json').read_bytes(), original)
        self.assertFalse(RUNNER.transfer_reconciliation_changed(proof))

    def test_other_run_or_device_is_not_admitted(self):
        self.args.restore_from = 'other-run'
        with self.assertRaisesRegex(RuntimeError, 'known same-iOS'):
            self.validate()
        self.args.restore_from = self.run
        self.args.device = 'emulator-5582'
        with self.assertRaisesRegex(RuntimeError, 'known same-iOS'):
            self.validate()

    def test_production_source_change_is_rejected(self):
        self.app_identity['files']['lib/app.dart'] = '9' * 64
        with self.assertRaisesRegex(RuntimeError, 'Production source changed'):
            self.validate()

    def test_original_report_hash_binding_is_required(self):
        self.report['elapsedSeconds'] = 999
        (self.output / 'result.json').write_text(json.dumps(self.report))
        with self.assertRaisesRegex(RuntimeError, 'original failed report'):
            self.validate()

    def test_late_events_must_match_original_prefix_and_live_journal(self):
        self.events[0] = {**self.events[0], 'node_public_key': self.imported_key}
        self.save()
        with self.assertRaisesRegex(RuntimeError, 'late journal hash differs'):
            self.validate()

    def test_live_event_after_closure_is_not_ignored(self):
        with (self.evidence / 'events.jsonl').open('a') as stream:
            stream.write(json.dumps({**self.events[-1], 'event': 'bfa_burn_requested'}) + '\n')
        with self.assertRaisesRegex(RuntimeError, 'original prefix or live journal'):
            self.validate()

    def test_additional_send_after_original_transfer_is_rejected(self):
        self.events.insert(14, {**self.events[12], 'amount_units': 1})
        self.save()
        with self.assertRaisesRegex(RuntimeError, 'late journal hash differs'):
            self.validate()

    def test_duplicate_identity_is_rejected(self):
        self.events[8]['node_public_key'] = self.original_key
        self.save()
        with self.assertRaisesRegex(RuntimeError, 'late journal hash differs'):
            self.validate()

    def test_mint_acknowledgement_invoice_and_amount_remain_bound(self):
        self.acks[self.ids[2]]['mint']['invoice'] = 'different-public-invoice'
        self.save()
        with self.assertRaisesRegex(RuntimeError, 'mint acknowledgement differs'):
            self.validate()

    def test_funding_bool_cannot_alias_integer_amount(self):
        self.acks[self.ids[0]]['amount_sats'] = True
        self.save()
        with self.assertRaisesRegex(RuntimeError, 'funding acknowledgement differs'):
            self.validate()

    def test_two_funding_receipts_cannot_alias_the_same_transaction(self):
        self.acks[self.ids[3]]['txid'] = self.acks[self.ids[0]]['txid']
        self.save()
        with self.assertRaisesRegex(RuntimeError, 'two distinct prior funding'):
            self.validate()

    def test_closed_snapshot_tampering_is_rejected(self):
        (self.output / 'private-device-state/extra.db').write_text('different closed state')
        with self.assertRaisesRegex(RuntimeError, 'snapshot content hash differs'):
            self.validate()

    def test_end_gate_detects_acknowledgement_and_original_journal_drift(self):
        _, _, proof = self.validate()
        path = self.evidence / 'commands' / (self.ids[2] + '.json')
        original = path.read_bytes()
        path.write_text('{}')
        self.assertTrue(RUNNER.transfer_reconciliation_changed(proof))
        path.write_bytes(original)
        self.assertFalse(RUNNER.transfer_reconciliation_changed(proof))
        (self.evidence / 'events.jsonl').write_text('')
        self.assertTrue(RUNNER.transfer_reconciliation_changed(proof))

    def test_end_gate_detects_original_closed_wallet_bytes_changed_after_admission(self):
        _, _, proof = self.validate()
        (self.output / 'private-device-state/extra.db').write_text('late native state drift')
        self.assertTrue(RUNNER.transfer_reconciliation_changed(proof))

    def prepare_closed_continuation(self):
        self.original, self.expected, self.proof = self.validate()
        self.args.checkpoint_from = RUNNER.TRANSFER_RECONCILIATION_CHECKPOINT
        self.checkpoint_output = self.evidence / self.args.checkpoint_from
        self.checkpoint_output.mkdir()
        snapshot = self.checkpoint_output / 'private-device-state'
        RUNNER.shutil.copytree(self.output / 'private-device-state', snapshot)
        (snapshot / 'latest-native-progress.db').write_text('newer native state, never roll back')
        self.checkpoint_backup = {'status': 'saved', 'nativeClosed': True,
                                  'filesManifestSha256': RUNNER.tree_digest(snapshot)}
        def event(name, **fields):
            return {'event': name, 'run_id': self.args.checkpoint_from, 'role': 'app-ios27', **fields}
        self.checkpoint_ids = [self.args.checkpoint_from + '-app-ios27-' + str(i) for i in (1, 2)]
        self.checkpoint_events = [
            event('test_started', stage='reconcile-transfer'), event('public_network_preflight'),
            event('fixture_transfer_validation_requested', id=self.checkpoint_ids[0], storage_run_id=self.run),
            event('test_failed', code='qa_transfer_original_native_checkpoint_changed',
                  diagnostics=[], sensitive_screen_active=False),
            event('test_cleanup', native_disposed=True),
            event('fixture_backup_requested', id=self.checkpoint_ids[1], native_disposed=True, stage='reconcile-transfer'),
            event('fixture_backup_verified'),
        ]
        (self.checkpoint_output / 'flutter.log').write_text('public continuation fixture')
        self.checkpoint_report = {**self.report, 'runId': self.args.checkpoint_from,
            'stage': 'reconcile-transfer', 'restoredFromRun': self.run,
            'restoreEvidenceChangedDuringRun': False, 'reconciliationEvidenceChangedDuringRun': False,
            'reconciliationSource': self.proof.copy(), 'privateFixtureBackup': self.checkpoint_backup,
            'events': self.checkpoint_events,
            'flutterLogSha256': RUNNER.digest(self.checkpoint_output / 'flutter.log')}
        (self.checkpoint_output / 'source-before.json').write_bytes((self.output / 'source-before.json').read_bytes())
        (self.checkpoint_output / 'invocation.json').write_text(json.dumps({
            'schemaVersion': 1, 'runId': self.args.checkpoint_from, 'device': self.args.device,
            'package': RUNNER.PACKAGE, 'stage': 'reconcile-transfer', 'storageRunId': self.run,
        }))
        (self.checkpoint_output / 'preservation.json').write_text(json.dumps({
            'schemaVersion': 1, 'runId': self.args.checkpoint_from, 'device': self.args.device,
            'package': RUNNER.PACKAGE, 'storageRunId': self.run, 'backup': self.checkpoint_backup,
        }))
        (self.evidence / 'commands' / (self.checkpoint_ids[0] + '.json')).write_text(
            json.dumps({'ok': True, 'expected_transfer': self.expected}))
        (self.evidence / 'commands' / (self.checkpoint_ids[1] + '.json')).write_text(
            json.dumps({'ok': True, 'backup_verified': True}))
        self.save_checkpoint()
        for name, value in [
                ('TRANSFER_RECONCILIATION_CHECKPOINT_REPORT', RUNNER.digest(self.checkpoint_output / 'result.json')),
                ('TRANSFER_RECONCILIATION_CHECKPOINT_MANIFEST', self.checkpoint_backup['filesManifestSha256'])]:
            fixture_patch = patch.object(RUNNER, name, value)
            fixture_patch.start()
            self.addCleanup(fixture_patch.stop)

    def save_checkpoint(self):
        (self.checkpoint_output / 'result.json').write_text(json.dumps(self.checkpoint_report))
        (self.evidence / 'events.jsonl').write_text(
            ''.join(json.dumps(event) + '\n' for event in self.events + self.checkpoint_events))

    def validate_checkpoint(self):
        return RUNNER.transfer_reconciliation_checkpoint(self.args, self.expected, self.proof,
                                                         self.sdk, self.app_identity, self.sdk_identity,
                                                         'a' * 64, 'b' * 64)

    def test_continuation_uses_latest_closed_bytes_without_changing_original_intent(self):
        self.prepare_closed_continuation()
        original_bytes = (self.output / 'result.json').read_bytes()
        with patch.object(RUNNER.subprocess, 'Popen') as launch, \
                patch.object(RUNNER.urllib.request, 'urlopen') as request:
            report, source = self.validate_checkpoint()
        launch.assert_not_called()
        request.assert_not_called()
        self.assertEqual(source, self.checkpoint_output / 'private-device-state')
        self.assertTrue((source / 'latest-native-progress.db').is_file())
        self.assertNotEqual(report['privateFixtureBackup'], self.original['privateFixtureBackup'])
        self.assertEqual(self.expected['txid'], self.txid)
        self.assertEqual((self.output / 'result.json').read_bytes(), original_bytes)
        self.assertFalse(RUNNER.transfer_reconciliation_changed(self.proof))

    def test_continuation_rejects_another_failure_or_financial_event(self):
        self.prepare_closed_continuation()
        self.checkpoint_events[3]['code'] = 'qa_other_failure'
        self.save_checkpoint()
        with self.assertRaisesRegex(RuntimeError, 'closed A checkpoint report hash differs'):
            self.validate_checkpoint()
        self.checkpoint_events[3]['code'] = 'qa_transfer_original_native_checkpoint_changed'
        self.checkpoint_events.insert(3, {**self.checkpoint_events[0], 'event': 'fund_requested'})
        self.save_checkpoint()
        with self.assertRaisesRegex(RuntimeError, 'closed A checkpoint report hash differs'):
            self.validate_checkpoint()

    def test_continuation_rejects_other_device_or_sdk_config(self):
        self.prepare_closed_continuation()
        self.checkpoint_report['consumerConfigSha256AtEnd'] = '9' * 64
        self.save_checkpoint()
        with self.assertRaisesRegex(RuntimeError, 'closed A checkpoint report hash differs'):
            self.validate_checkpoint()

    def test_continuation_rejects_modified_original_intent_ack(self):
        self.prepare_closed_continuation()
        path = self.evidence / 'commands' / (self.checkpoint_ids[0] + '.json')
        value = json.loads(path.read_text())
        value['expected_transfer']['txid'] = '9' * 64
        path.write_text(json.dumps(value))
        with self.assertRaisesRegex(RuntimeError, 'acknowledgement differs'):
            self.validate_checkpoint()

    def test_continuation_rejects_latest_backup_corruption(self):
        self.prepare_closed_continuation()
        (self.checkpoint_output / 'private-device-state/extra.db').write_text('corrupt')
        with self.assertRaisesRegex(RuntimeError, 'snapshot content hash differs'):
            self.validate_checkpoint()

    def test_continuation_end_gate_binds_latest_backup_and_acks(self):
        self.prepare_closed_continuation()
        self.validate_checkpoint()
        path = self.checkpoint_output / 'private-device-state/latest-native-progress.db'
        original_bytes = path.read_bytes()
        path.write_text('late drift')
        self.assertTrue(RUNNER.transfer_reconciliation_changed(self.proof))
        path.write_bytes(original_bytes)
        self.assertFalse(RUNNER.transfer_reconciliation_changed(self.proof))
        (self.evidence / 'commands' / (self.checkpoint_ids[1] + '.json')).write_text('{}')
        self.assertTrue(RUNNER.transfer_reconciliation_changed(self.proof))


class SdkProvenanceTests(unittest.TestCase):
    """Use real local Git packages; no Pub, network, emulator or wallet access."""
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.app = self.root / 'app'
        self.sdk = self.root / 'pub cache with spaces/actual-sdk'
        self.app.mkdir()
        self.sdk.mkdir(parents=True)
        self.git('init', '-q')
        self.git('config', 'user.name', 'Runner Fixture')
        self.git('config', 'user.email', 'fixture@example.test')
        (self.sdk / 'lib').mkdir()
        (self.sdk / 'lib/sdk.dart').write_text('const fixtureVersion = 1;\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'Disposable fixture')
        self.commit = self.git('rev-parse', 'HEAD').strip()
        self.pubspec = self.app / 'pubspec.yaml'
        self.pubspec.write_text(
            'name: runner_fixture\ndependencies:\n  rgb_sdk_flutter:\n'
            '    git:\n      url: ' + RUNNER.SDK_REPOSITORY + '\n'
            '      ref: ' + self.commit + '\n')
        self.lock = self.app / 'pubspec.lock'
        self.lock.write_text(
            'packages:\n  rgb_sdk_flutter:\n    description:\n'
            '      path: "."\n      ref: ' + self.commit + '\n'
            '      resolved-ref: ' + self.commit + '\n'
            '      url: "' + RUNNER.SDK_REPOSITORY + '"\n'
            '    source: git\n    version: "0.2.0-beta.2"\n')
        self.package_config = self.app / '.dart_tool/package_config.json'
        self.package_config.parent.mkdir()
        self.package_config.write_text(json.dumps({'configVersion': 2, 'packages': [{
            'name': 'rgb_sdk_flutter', 'rootUri': self.sdk.as_uri() + '/',
            'packageUri': 'lib/', 'languageVersion': '3.11',
        }]}))
        self.root_patch = patch.object(RUNNER, 'ROOT', self.app)
        self.root_patch.start()

    def tearDown(self):
        self.root_patch.stop()
        self.temporary.cleanup()

    def git(self, *arguments):
        return subprocess.check_output(['git', *arguments], cwd=self.sdk, text=True,
                                       stderr=subprocess.PIPE)

    def test_exact_locked_git_package_is_resolved_from_encoded_uri(self):
        dependency = RUNNER.resolved_sdk_dependency()
        self.assertEqual(dependency['root'], str(self.sdk.resolve()))
        self.assertEqual(dependency['ref'], self.commit)
        self.assertEqual(dependency['repository'], RUNNER.SDK_REPOSITORY)
        self.assertEqual(dependency['packageConfigSha256'], RUNNER.digest(self.package_config))

    def test_relative_package_uri_is_resolved_from_package_config_directory(self):
        config = json.loads(self.package_config.read_text())
        config['packages'][0]['rootUri'] = '../../pub%20cache%20with%20spaces/actual-sdk/'
        self.package_config.write_text(json.dumps(config))
        self.assertEqual(RUNNER.resolved_sdk_dependency()['root'], str(self.sdk.resolve()))

    def test_branch_ref_is_rejected_even_when_checkout_is_clean(self):
        self.pubspec.write_text(self.pubspec.read_text().replace(self.commit, 'upgrade-branch'))
        with self.assertRaisesRegex(RuntimeError, 'full immutable Git ref'):
            RUNNER.resolved_sdk_dependency()

    def test_mismatched_lock_resolved_ref_is_rejected(self):
        self.lock.write_text(self.lock.read_text().replace('resolved-ref: ' + self.commit,
                                                         'resolved-ref: ' + '0' * 40))
        with self.assertRaisesRegex(RuntimeError, 'lock does not match'):
            RUNNER.resolved_sdk_dependency()

    def test_noncanonical_repository_is_rejected(self):
        self.pubspec.write_text(self.pubspec.read_text().replace(RUNNER.SDK_REPOSITORY,
                                                               'https://example.test/sdk.git'))
        with self.assertRaisesRegex(RuntimeError, 'canonical repository'):
            RUNNER.resolved_sdk_dependency()

    def test_override_file_and_inline_sdk_override_are_rejected(self):
        override = self.app / 'pubspec_overrides.yaml'
        override.write_text('dependency_overrides: {}\n')
        with self.assertRaisesRegex(RuntimeError, 'no pubspec_overrides'):
            RUNNER.resolved_sdk_dependency()
        override.unlink()
        self.pubspec.write_text(self.pubspec.read_text()
                                + 'dependency_overrides:\n  rgb_sdk_flutter:\n    path: ../local-sdk\n')
        with self.assertRaisesRegex(RuntimeError, 'SDK dependency override'):
            RUNNER.resolved_sdk_dependency()

    def test_duplicate_resolved_sdk_entry_is_rejected(self):
        config = json.loads(self.package_config.read_text())
        config['packages'].append(config['packages'][0])
        self.package_config.write_text(json.dumps(config))
        with self.assertRaisesRegex(RuntimeError, 'missing or ambiguous'):
            RUNNER.resolved_sdk_dependency()

    def test_stale_package_config_checkout_is_rejected(self):
        (self.sdk / 'lib/sdk.dart').write_text('const fixtureVersion = 2;\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'Another immutable fixture')
        with self.assertRaisesRegex(RuntimeError, 'not clean at the locked commit'):
            RUNNER.resolved_sdk_dependency()

    def test_modified_and_untracked_resolved_sdk_sources_are_rejected(self):
        source = self.sdk / 'lib/sdk.dart'
        original = source.read_text()
        source.write_text('modified source')
        with self.assertRaisesRegex(RuntimeError, 'not clean at the locked commit'):
            RUNNER.resolved_sdk_dependency()
        source.write_text(original)
        (self.sdk / 'lib/injected.dart').write_text('untracked source')
        with self.assertRaisesRegex(RuntimeError, 'not clean at the locked commit'):
            RUNNER.resolved_sdk_dependency()

    def prepare_runner(self):
        self.evidence = self.root / 'evidence'
        self.evidence.mkdir()
        self.stack = self.root / 'shared-stack'
        (self.stack / 'artifacts').mkdir(parents=True)
        contract = self.stack / 'artifacts/public-contract.rgb'
        contract.write_text('public contract fixture')
        self.consumer = self.stack / 'artifacts/consumer-config.json'
        self.consumer.write_text(json.dumps({
            'environment': 'LOCAL TEST ONLY', 'network': 'regtest', 'evm_chain_id': 42161,
            'asset': {'public_contract': str(contract), 'sha256': RUNNER.digest(contract)},
        }))
        self.config = self.app / 'config/shared-stack.ios.local.json'
        self.config.parent.mkdir()
        self.config.write_text('{"EXPLORER_URL":"http://127.0.0.1:18094"}')
        (self.app / '.gitignore').write_text('.dart_tool/\nconfig/*.local.json\n')
        for arguments in [('init', '-q'), ('config', 'user.name', 'Runner Fixture'),
                          ('config', 'user.email', 'fixture@example.test'),
                          ('add', '.'), ('commit', '-qm', 'Disposable app fixture')]:
            subprocess.run(['git', *arguments], cwd=self.app, check=True,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return SimpleNamespace(device='857A20C2-601C-4864-AFEB-B525D1B5B4D7',
                               run_id='provenance-run', restore_from=None, stage='full')

    def simulated_run(self, mutate=None):
        args = self.prepare_runner()
        started = False
        actual_process = subprocess.Popen
        class FinishedProcess:
            polls = 0
            def poll(self):
                self.polls += 1
                return None if self.polls == 1 else 0
            def wait(self):
                return 0
        def launch(*arguments, **options):
            nonlocal started
            if arguments[0][0] == 'git':
                return actual_process(*arguments, **options)
            self.assertEqual(arguments[0][1], 'drive')
            self.assertIn('--no-start-paused', arguments[0])
            self.assertIn('--keep-app-running', arguments[0])
            self.assertNotIn('--start-paused', arguments[0])
            started = True
            if mutate:
                mutate()
            return FinishedProcess()
        events = [{'event': 'fixture_backup_requested', 'id': 'closed-fixture'},
                  {'event': 'test_passed'}, {'event': 'test_cleanup', 'native_disposed': True}]
        with patch.object(RUNNER, 'EVIDENCE', self.evidence), \
                patch.object(RUNNER, 'SHARED', self.stack), \
                patch.object(RUNNER.urllib.request, 'urlopen',
                             return_value=io.BytesIO(b'{"ready":true,"mutations":false}')), \
                patch.object(RUNNER, 'read_events', side_effect=lambda run: events if started else []), \
                patch.object(RUNNER, 'preserve_and_ack',
                             return_value={'status': 'saved', 'nativeClosed': True}), \
                patch.object(RUNNER.subprocess, 'Popen', side_effect=launch), \
                patch.object(RUNNER.time, 'sleep'), patch('builtins.print'):
            code = RUNNER.run_qualification(args, None)
        output = self.evidence / args.run_id
        return code, json.loads((output / 'result.json').read_text()), output

    def test_success_hashes_actual_resolved_sdk_at_both_ends(self):
        code, report, output = self.simulated_run()
        self.assertEqual(code, 0)
        self.assertEqual(report['status'], 'passed')
        self.assertEqual(report['launchFlags'], ['--no-start-paused', '--keep-app-running'])
        self.assertEqual(report['sdkDependencyBefore']['root'], str(self.sdk.resolve()))
        before = json.loads((output / 'source-before.json').read_text())
        after = json.loads((output / 'source-after.json').read_text())
        self.assertEqual(before['sdk']['files']['lib/sdk.dart'], RUNNER.digest(self.sdk / 'lib/sdk.dart'))
        self.assertEqual(before, after)

    def simulated_early_driver_exit(self, late_cleanup):
        args = self.prepare_runner()
        now = [0.0]
        started = False
        launches = []
        acknowledgements = []
        actual_process = subprocess.Popen
        output = self.evidence / args.run_id
        class DisconnectedProcess:
            def poll(self):
                return 1
            def wait(self):
                return 1
            def terminate(self):
                raise AssertionError('Driver exit must not terminate the native app')
            def kill(self):
                raise AssertionError('Driver exit must not kill the native app')
        def launch(*arguments, **options):
            nonlocal started
            if arguments[0][0] == 'git':
                return actual_process(*arguments, **options)
            started = True
            launches.append(arguments[0])
            return DisconnectedProcess()
        def events(run_id):
            self.assertEqual(run_id, args.run_id)
            if not started or not late_cleanup or now[0] < 300:
                return []
            result = [{'event': 'test_passed'},
                      {'event': 'test_cleanup', 'native_disposed': True}]
            if now[0] >= 300.25:
                result.append({'event': 'fixture_backup_requested', 'id': 'late-closed-fixture',
                               'native_disposed': True})
            return result
        def preserve(event, actual_args, actual_output):
            self.assertTrue(event['native_disposed'])
            self.assertEqual(actual_args, args)
            self.assertEqual(actual_output, output)
            snapshot = output / 'private-device-state'
            snapshot.mkdir()
            (snapshot / 'wallet.db').write_text('closed disposable wallet fixture')
            return {'status': 'saved', 'nativeClosed': True,
                    'filesManifestSha256': RUNNER.sync_private_tree(snapshot)}
        def acknowledge(event_id, payload):
            proof = json.loads((output / 'preservation.json').read_text())
            RUNNER.verify_closed_backup(output, args.device, proof['backup'])
            self.assertGreaterEqual(now[0], 300.25)
            acknowledgements.append((event_id, payload))
        def advance(seconds):
            now[0] += seconds
        with patch.object(RUNNER, 'EVIDENCE', self.evidence), \
                patch.object(RUNNER, 'SHARED', self.stack), \
                patch.object(RUNNER.urllib.request, 'urlopen',
                             return_value=io.BytesIO(b'{"ready":true,"mutations":false}')), \
                patch.object(RUNNER, 'read_events', side_effect=events), \
                patch.object(RUNNER, 'preserve', side_effect=preserve), \
                patch.object(RUNNER, 'write_ack', side_effect=acknowledge), \
                patch.object(RUNNER.subprocess, 'Popen', side_effect=launch), \
                patch.object(RUNNER.time, 'sleep', side_effect=advance), \
                patch.object(RUNNER.time, 'monotonic', side_effect=lambda: now[0]), \
                patch('builtins.print'):
            code = RUNNER.run_qualification(args, None)
        self.assertEqual(len(launches), 1)
        return code, json.loads((output / 'result.json').read_text()), output, now[0], acknowledgements

    def test_early_driver_failure_still_preserves_late_native_cleanup_without_passing(self):
        code, report, output, elapsed, acknowledgements = self.simulated_early_driver_exit(True)
        self.assertEqual(code, 1)
        self.assertEqual(report['exitCode'], 1)
        self.assertEqual(report['status'], 'failed')
        self.assertIsNone(report['runnerError'])
        self.assertEqual(elapsed, 300.25)
        self.assertEqual(acknowledgements, [('late-closed-fixture', {'backup_verified': True})])
        RUNNER.verify_closed_backup(output, report['device'], report['privateFixtureBackup'])
        self.assertTrue(any(event['event'] == 'test_cleanup' for event in report['events']))
        self.assertTrue(any(event['event'] == 'test_passed' for event in report['events']))

    def test_early_driver_exit_grace_expires_without_backup_or_relaunch(self):
        code, report, output, elapsed, acknowledgements = self.simulated_early_driver_exit(False)
        self.assertEqual(code, 1)
        self.assertEqual(report['status'], 'failed')
        self.assertEqual(report['exitCode'], 1)
        self.assertEqual(elapsed, 360)
        self.assertEqual(report['privateFixtureBackup'], {'status': 'unavailable'})
        self.assertEqual(acknowledgements, [])
        self.assertFalse((output / 'preservation.json').exists())
        self.assertEqual(report['events'], [])

    def test_ignored_app_configuration_drift_fails_otherwise_successful_run(self):
        code, report, _ = self.simulated_run(lambda: self.config.write_text('{"changed":true}'))
        self.assertEqual(code, 1)
        self.assertTrue(report['configurationChangedDuringRun'])
        self.assertFalse(report['appSourceChangedDuringRun'])
        self.assertNotEqual(report['appConfigSha256'], report['appConfigSha256AtEnd'])

    def test_consumer_configuration_drift_fails_otherwise_successful_run(self):
        code, report, _ = self.simulated_run(lambda: self.consumer.write_text('{"changed":true}'))
        self.assertEqual(code, 1)
        self.assertTrue(report['configurationChangedDuringRun'])
        self.assertNotEqual(report['consumerConfigSha256'], report['consumerConfigSha256AtEnd'])

    def test_deleted_configuration_retains_failed_result_and_events(self):
        code, report, _ = self.simulated_run(lambda: self.config.unlink())
        self.assertEqual(code, 1)
        self.assertIsNone(report['appConfigSha256AtEnd'])
        self.assertTrue(report['configurationChangedDuringRun'])
        self.assertTrue(any(event['event'] == 'test_passed' for event in report['events']))

    def test_actual_sdk_mutation_fails_otherwise_successful_run(self):
        code, report, _ = self.simulated_run(
            lambda: (self.sdk / 'lib/sdk.dart').write_text('changed during qualification'))
        self.assertEqual(code, 1)
        self.assertTrue(report['sdkSourceChangedDuringRun'])
        self.assertEqual(report['sdkDependencyAfter'], {'validationError': 'RuntimeError'})

    def test_package_config_drift_fails_otherwise_successful_run(self):
        def mutate():
            config = json.loads(self.package_config.read_text())
            config['packages'][0]['rootUri'] = 'https://example.test/sdk/'
            self.package_config.write_text(json.dumps(config))
        code, report, _ = self.simulated_run(mutate)
        self.assertEqual(code, 1)
        self.assertTrue(report['sdkSourceChangedDuringRun'])
        self.assertEqual(report['sdkDependencyAfter'], {'validationError': 'RuntimeError'})

    def test_missing_sdk_checkout_retains_failed_result_and_events(self):
        code, report, output = self.simulated_run(lambda: self.sdk.rename(self.root / 'moved-sdk'))
        self.assertEqual(code, 1)
        self.assertTrue(report['sdkSourceChangedDuringRun'])
        after = json.loads((output / 'source-after.json').read_text())
        self.assertEqual(after['sdk'], {'validationError': 'FileNotFoundError'})
        self.assertTrue(any(event['event'] == 'test_passed' for event in report['events']))

    def test_invalid_sdk_is_rejected_before_invocation_or_process_launch(self):
        args = self.prepare_runner()
        (self.sdk / 'lib/sdk.dart').write_text('unreviewed source')
        actual_process = subprocess.Popen
        device_launches = []
        def launch(command, **options):
            if command[0] == 'git':
                return actual_process(command, **options)
            device_launches.append(command)
            raise AssertionError('Unvalidated device process launch')
        with patch.object(RUNNER, 'EVIDENCE', self.evidence), \
                patch.object(RUNNER, 'SHARED', self.stack), \
                patch.object(RUNNER.urllib.request, 'urlopen',
                             return_value=io.BytesIO(b'{"ready":true,"mutations":false}')), \
                patch.object(RUNNER.subprocess, 'Popen', side_effect=launch), \
                self.assertRaisesRegex(RuntimeError, 'not clean at the locked commit'):
            RUNNER.run_qualification(args, None)
        self.assertEqual(device_launches, [])
        self.assertFalse((self.evidence / args.run_id / 'invocation.json').exists())


    def test_unready_android_framework_creates_no_output_or_invocation(self):
        args = self.prepare_runner()
        args.device = 'emulator-5582'
        with patch.object(RUNNER, 'EVIDENCE', self.evidence), \
                patch.object(RUNNER.subprocess, 'Popen') as launch, \
                patch.object(RUNNER.subprocess, 'run', side_effect=[
                    SimpleNamespace(returncode=0, stdout='1'),
                    SimpleNamespace(returncode=0, stdout='Service package: not found'),
                    SimpleNamespace(returncode=0, stdout='Service activity: not found')]), \
                self.assertRaisesRegex(RuntimeError, 'framework is not ready'):
            RUNNER.run_qualification(args, None)
        launch.assert_not_called()
        self.assertFalse((self.evidence / args.run_id).exists())


class KnownPretestAdmissionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.app, self.stack, self.evidence = (self.root / name for name in ('app', 'stack', 'evidence'))
        (self.app / 'config').mkdir(parents=True)
        (self.stack / 'artifacts').mkdir(parents=True)
        config = self.app / 'config/shared-stack.android.local.json'
        consumer = self.stack / 'artifacts/consumer-config.json'
        config.write_text('{}')
        consumer.write_text('{}')
        self.config_sha, self.consumer_sha = RUNNER.digest(config), RUNNER.digest(consumer)
        for key, value in [('ROOT', self.app), ('SHARED', self.stack), ('EVIDENCE', self.evidence)]:
            self.patch_value(key, value)
        self.run, self.device = 'aster-full-android17-20261015-i', 'emulator-5582'
        self.output = self.evidence / self.run
        self.output.mkdir(parents=True, mode=0o700)
        self.sdk = {'root': str(self.root / 'sdk'), 'ref': 'd' * 40,
                    'repository': RUNNER.SDK_REPOSITORY, 'packageConfigSha256': 'a' * 64}
        self.app_identity = {'files': {'lib/app.dart': '1' * 64}, 'filesSha256': '1' * 64}
        self.sdk_identity = {'files': {'lib/sdk.dart': '2' * 64}, 'filesSha256': '2' * 64}
        self.patch_value('resolved_sdk_dependency', lambda: self.sdk)
        self.patch_value('source_identity', lambda path: self.app_identity if path == self.app else self.sdk_identity)
        self.prior_output = self.evidence / 'aster-full-android17-20261015-h'
        self.prior_output.mkdir()
        prior_archive = self.prior_output / 'private-device-state.tar'
        prior_archive.write_bytes(b'closed prior fixture archive')
        self.prior_backup = {'status': 'saved', 'nativeClosed': True,
                             'sha256': RUNNER.digest(prior_archive), 'bytes': prior_archive.stat().st_size}
        self.write(self.prior_output / 'invocation.json', self.invocation(self.prior_output.name))
        self.write(self.prior_output / 'preservation.json', {
            'schemaVersion': 1, 'runId': self.prior_output.name, 'device': self.device,
            'package': RUNNER.PACKAGE, 'storageRunId': self.prior_output.name, 'backup': self.prior_backup})
        self.write(self.prior_output / 'result.json', {'status': 'failed'})
        self.write(self.prior_output / 'source-before.json', {'public': 'prior fixture'})
        self.prior = {'runId': self.prior_output.name, 'archiveBytes': self.prior_backup['bytes'],
                      'archiveSha256': self.prior_backup['sha256'], 'boundFiles': {
                          name: RUNNER.digest(self.prior_output / name) for name in
                          ('invocation.json', 'preservation.json', 'result.json', 'source-before.json')}}
        self.write(self.output / 'invocation.json', self.invocation(self.run))
        self.write(self.output / 'source-before.json', {'app': self.app_identity, 'sdk': self.sdk_identity,
            'sdkDependency': self.sdk, 'appConfigSha256': self.config_sha, 'consumerConfigSha256': self.consumer_sha})
        (self.output / 'flutter.log').write_text('public pretest startup fixture')
        self.resume_intent = {'operation': 'VMService.resume', 'endpointClass': 'existing-native-ADB-forward',
            'currentAppAndSdkExactlyMatchLaunchManifest': True, 'zeroRunEvents': True,
            'runEventCountBefore': 0, 'maxAttempts': 1, 'timeoutSeconds': 5,
            'runId': self.run, 'device': self.device, 'pid': 1234,
            'sourceManifestSha256': RUNNER.digest(self.output / 'source-before.json'), 'isolateId': 'isolates/123'}
        self.resume_result = {'attemptCount': 1, 'status': 'outcome_uncertain_no_retry', 'retryPermitted': False,
                              'runId': self.run, 'device': self.device, 'pid': 1234, 'isolateId': 'isolates/123'}
        archive = self.output / 'pre-test-private-app-data.tar'
        archive.write_bytes(b'closed credential and device protected app fixture')
        archive.chmod(0o600)
        self.archive = {'name': archive.name, 'bytes': archive.stat().st_size, 'sha256': RUNNER.digest(archive),
                        'roots': ['/data/user/0/' + RUNNER.PACKAGE, '/data/user_de/0/' + RUNNER.PACKAGE],
                        'mode': '0600', 'outputDirectoryMode': '0700'}
        absent = {'absent': True, 'path': '/data/user/0/' + RUNNER.PACKAGE + '/files/aster_full_wallet_qa/' + self.run}
        self.certificate = {'schemaVersion': 1, 'runId': self.run, 'device': self.device,
            'package': RUNNER.PACKAGE, 'pid': 1234, 'operationSourceSha256': '3' * 64,
            'closureBasis': 'host-stopped-before-qa-storage-creation', 'nativeDisposedObserved': False,
            'normalDisposalAcknowledgementWritten': False, 'normalPreservationWritten': False,
            'infrastructureStarted': False, 'containersCreated': False, 'stateReset': False,
            'normalResultUntouched': True, 'sourceMatchesLaunchManifestBeforeAndAfter': True,
            'appFilesSha256': '1' * 64, 'sdkFilesSha256': '2' * 64,
            'appConfigSha256': self.config_sha, 'consumerConfigSha256': self.consumer_sha,
            'beforeStop': {'events': {'runEventCount': 0}, 'fixture': dict(absent), 'process': {'pid': 1234}},
            'hostDriver': {'absentAfter': True, 'pid': 1235, 'coordinatorPid': 1236,
                           'coordinatorStopRequested': False, 'termSent': False,
                           'exitBasis': 'exited-after-app-disconnect-no-host-signal-sent'},
            'stopTiming': {'requestSentOnce': True}, 'archive': self.archive, 'priorClosedRun': self.prior,
            'priorFixtureRegularFiles': {'count': 1, 'equal': True, 'recordsSha256': '4' * 64}}
        for phase in ('afterStop', 'afterQuiescence', 'afterArchive'):
            self.certificate[phase] = {'events': {'runEventCount': 0}, 'fixture': dict(absent),
                                      'process': {'expectedPidAbsent': True, 'packagePids': []}}
        self.report = {'schemaVersion': 1, 'runId': self.run, 'device': self.device, 'stage': 'full',
            'status': 'failed', 'exitCode': 1, 'runnerError': None, 'events': [],
            'privateFixtureBackup': {'status': 'unavailable'},
            'flutterLogSha256': RUNNER.digest(self.output / 'flutter.log'),
            'appConfigSha256': self.config_sha, 'appConfigSha256AtEnd': self.config_sha,
            'consumerConfigSha256': self.consumer_sha, 'consumerConfigSha256AtEnd': self.consumer_sha,
            'sdkDependencyBefore': self.sdk, 'sdkDependencyAfter': self.sdk}
        for key in ('appSourceChangedDuringRun', 'sdkSourceChangedDuringRun', 'configurationChangedDuringRun',
                    'infrastructureStarted', 'containersCreated', 'stateReset'):
            self.report[key] = False
        self.pins = {'runId': self.run, 'device': self.device, 'resultSha256': '', 'certificateSha256': '',
                     'archiveSha256': self.archive['sha256'], 'archiveBytes': self.archive['bytes'],
                     'priorRunId': self.prior_output.name, 'priorArchiveSha256': self.prior_backup['sha256'],
                     'priorArchiveBytes': self.prior_backup['bytes'], 'priorRegularFiles': 1,
                     'priorRecordsSha256': '4' * 64}
        self.pins.update(closureBasis='host-stopped-before-qa-storage-creation',
                         operation='force-stop-exact-pretest-package-and-preserve',
                         resumeMode='one-uncertain-resume',
                         driverExitBasis='exited-after-app-disconnect-no-host-signal-sent')
        self.patch_value('KNOWN_PRETEST_FAILURES', {self.run: self.pins})
        self.save()

    def patch_value(self, name, value):
        mocked = patch.object(RUNNER, name, value)
        mocked.start()
        self.addCleanup(mocked.stop)

    @staticmethod
    def write(path, value):
        path.write_text(json.dumps(value))

    def invocation(self, run):
        return {'schemaVersion': 1, 'runId': run, 'device': self.device,
                'package': RUNNER.PACKAGE, 'stage': 'full', 'storageRunId': run}

    def save(self):
        self.write(self.output / 'targeted-resume-intent.json', self.resume_intent)
        self.resume_result['intentSha256'] = RUNNER.digest(self.output / 'targeted-resume-intent.json')
        self.write(self.output / 'targeted-resume-result.json', self.resume_result)
        self.certificate['boundFiles'] = {name: RUNNER.digest(self.output / name) for name in
            ('invocation.json', 'source-before.json', 'targeted-resume-intent.json', 'targeted-resume-result.json')}
        intent = {key: self.certificate[key] for key in ('runId', 'device', 'package', 'pid',
            'operationSourceSha256', 'beforeStop', 'priorClosedRun', 'boundFiles', 'appConfigSha256', 'consumerConfigSha256')}
        intent.update(operation='force-stop-exact-pretest-package-and-preserve', hostFlutterDrivePid=1235, coordinatorPid=1236)
        self.write(self.output / 'pre-test-recovery-intent.json', intent)
        self.certificate['recoveryIntentSha256'] = RUNNER.digest(self.output / 'pre-test-recovery-intent.json')
        self.write(self.output / 'pre-test-preservation.json', self.certificate)
        self.write(self.output / 'result.json', self.report)
        self.pins['certificateSha256'] = RUNNER.digest(self.output / 'pre-test-preservation.json')
        self.pins['resultSha256'] = RUNNER.digest(self.output / 'result.json')

    def admit(self):
        return RUNNER.known_pretest_failure_admission(self.device, self.run)

    def test_explicit_known_certificate_allows_next_launch_without_forging_native_closure(self):
        before = (self.output / 'result.json').read_bytes()
        with patch.object(RUNNER.subprocess, 'Popen') as launch, patch.object(RUNNER.urllib.request, 'urlopen') as network:
            admissions = RUNNER.assert_prior_device_preserved(self.device, [self.run])
        admission = admissions[0]
        launch.assert_not_called()
        network.assert_not_called()
        self.assertFalse(admission['nativeDisposedObserved'])
        self.assertFalse((self.output / 'preservation.json').exists())
        self.assertEqual((self.output / 'result.json').read_bytes(), before)
        self.assertFalse(RUNNER.known_pretest_admission_changed(admission))
        self.assertFalse(RUNNER.qualification_passed(0, True, False, {'status': 'unavailable'}, None, False))

    def test_default_guard_still_rejects_the_pretest_fixture(self):
        with self.assertRaises(RuntimeError):
            RUNNER.assert_prior_device_preserved(self.device)

    def test_other_run_and_device_cannot_use_exception(self):
        for device, run in [('emulator-1234', self.run), (self.device, 'some-other-run')]:
            with self.assertRaises(RuntimeError):
                RUNNER.known_pretest_failure_admission(device, run)

    def test_report_test_started_or_live_event_rejects_even_coherent_certificate(self):
        self.report['events'] = [{'event': 'test_started'}]
        self.save()
        with self.assertRaises(RuntimeError):
            self.admit()
        self.report['events'] = []
        self.save()
        (self.evidence / 'events.jsonl').write_text(json.dumps({'event': 'test_started', 'run_id': self.run})+'\n')
        with self.assertRaises(RuntimeError):
            self.admit()

    def test_any_created_namespace_or_remaining_pid_rejects(self):
        self.certificate['afterQuiescence']['fixture']['absent'] = False
        self.save()
        with self.assertRaises(RuntimeError):
            self.admit()
        self.certificate['afterQuiescence']['fixture']['absent'] = True
        self.certificate['afterArchive']['process']['packagePids'] = [1234]
        self.save()
        with self.assertRaises(RuntimeError):
            self.admit()

    def test_forged_native_disposal_or_normal_preservation_is_not_accepted(self):
        self.certificate['nativeDisposedObserved'] = True
        self.save()
        with self.assertRaises(RuntimeError):
            self.admit()
        self.certificate['nativeDisposedObserved'] = False
        self.save()
        (self.output / 'preservation.json').write_text('{}')
        with self.assertRaises(RuntimeError):
            self.admit()

    def test_credential_data_archive_and_old_funded_fixture_bytes_remain_bound(self):
        admission = self.admit()
        (self.output / self.archive['name']).write_bytes(b'x' * self.archive['bytes'])
        self.assertTrue(RUNNER.known_pretest_admission_changed(admission))
        with self.assertRaises(RuntimeError):
            self.admit()

    def test_old_funded_h_archive_drift_is_never_waived(self):
        (self.prior_output / 'private-device-state.tar').write_bytes(b'changed H')
        with self.assertRaises(RuntimeError):
            self.admit()

    def test_receipt_hash_and_current_production_or_config_drift_rejects(self):
        (self.output / 'targeted-resume-result.json').write_text('{}')
        with self.assertRaises(RuntimeError):
            self.admit()
        self.save()
        self.app_identity['files']['lib/app.dart'] = '9' * 64
        with self.assertRaises(RuntimeError):
            self.admit()
        self.app_identity['files']['lib/app.dart'] = '1' * 64
        (self.app / 'config/shared-stack.android.local.json').write_text('{"changed":true}')
        with self.assertRaises(RuntimeError):
            self.admit()

    def test_resume_retry_and_more_than_zero_events_in_any_phase_rejects(self):
        self.resume_result['attemptCount'] = 2
        self.save()
        with self.assertRaises(RuntimeError):
            self.admit()
        self.resume_result['attemptCount'] = 1
        self.certificate['afterStop']['events']['runEventCount'] = 1
        self.save()
        with self.assertRaises(RuntimeError):
            self.admit()

    def test_end_gate_notices_late_started_test_or_missing_original_report(self):
        admission = self.admit()
        (self.evidence / 'events.jsonl').write_text(json.dumps({'run_id': self.run, 'event': 'test_started'})+'\n')
        self.assertTrue(RUNNER.known_pretest_admission_changed(admission))
        (self.evidence / 'events.jsonl').unlink()
        (self.output / 'result.json').unlink()
        self.assertTrue(RUNNER.known_pretest_admission_changed(admission))

    def test_explicit_exception_does_not_waive_another_open_native_owner(self):
        other = self.evidence / 'another-unpreserved-wallet'
        other.mkdir()
        self.write(other / 'invocation.json', self.invocation(other.name))
        with self.assertRaises(RuntimeError):
            RUNNER.assert_prior_device_preserved(self.device, [self.run])

    def test_changed_isolate_or_private_archive_permissions_are_rejected(self):
        self.resume_result['isolateId'] = 'isolates/other'
        self.save()
        with self.assertRaises(RuntimeError):
            self.admit()
        self.resume_result['isolateId'] = self.resume_intent['isolateId']
        self.save()
        admission = self.admit()
        (self.output / self.archive['name']).chmod(0o644)
        self.assertTrue(RUNNER.known_pretest_admission_changed(admission))
        with self.assertRaises(RuntimeError):
            self.admit()



    def add_install_failure_case(self):
        self.jrun = 'aster-full-android17-20261015-j'
        self.joutput = self.evidence / self.jrun
        self.joutput.mkdir(mode=0o700)
        for name in ('source-before.json', self.archive['name']):
            (self.joutput / name).write_bytes((self.output / name).read_bytes())
        (self.joutput / self.archive['name']).chmod(0o600)
        (self.joutput / 'flutter.log').write_text("cmd: Can't find service: package\n" * 3)
        self.write(self.joutput / 'invocation.json', self.invocation(self.jrun))
        self.jcertificate = json.loads(json.dumps(self.certificate))
        self.jcertificate.update(runId=self.jrun, pid=None,
            operation='preserve-prelaunch-install-failure', closureBasis='install-failed-before-app-start',
            zeroResumeAttempts=True, appStopRequested=False)
        for phase in ('beforeStop', 'afterStop', 'afterQuiescence', 'afterArchive'):
            self.jcertificate[phase]['fixture']['path'] = (
                '/data/user/0/' + RUNNER.PACKAGE + '/files/aster_full_wallet_qa/' + self.jrun)
            self.jcertificate[phase]['process'] = {'expectedPidAbsent': True, 'packagePids': []}
        self.jcertificate['hostDriver'] = {'pid': None, 'coordinatorPid': 5678,
            'absentAfter': True, 'coordinatorStopRequested': False, 'termSent': False,
            'exitBasis': 'exited-after-installation-failed-no-app-start',
            'originalDriverPidNotCaptured': True, 'matchingDriveProcesses': []}
        self.jcertificate['installationFailure'] = {'buildSucceeded': True, 'driverConnected': False,
            'error': "Can't find service: package", 'errorCount': 3}
        self.jcertificate['serviceHealthBefore'] = {'package': 'Service package: not found',
                                                   'activity': 'Service activity: not found'}
        self.jcertificate['priorStoppedRun'] = {'runId': self.run,
            'certificateSha256': self.pins['certificateSha256'],
            'failedResultSha256': self.pins['resultSha256'],
            'archiveSha256': self.archive['sha256'], 'archiveBytes': self.archive['bytes']}
        original_admission = RUNNER.known_pretest_failure_admission(self.device, self.run)
        self.jreport = dict(self.report, runId=self.jrun,
            priorLaunchAdmission={key: value for key, value in original_admission.items() if key != 'device'},
            priorLaunchEvidenceChangedDuringRun=False,
            flutterLogSha256=RUNNER.digest(self.joutput / 'flutter.log'))
        self.jpins = dict(self.pins, runId=self.jrun,
            operation='preserve-prelaunch-install-failure', closureBasis='install-failed-before-app-start',
            resumeMode='none', priorPretestRun=self.run, driverExitBasis='exited-after-installation-failed-no-app-start',
            packageServiceFailureCount=3)
        RUNNER.KNOWN_PRETEST_FAILURES[self.jrun] = self.jpins
        self.save_install_failure_case()

    def save_install_failure_case(self):
        self.jcertificate['boundFiles'] = {name: RUNNER.digest(self.joutput / name) for name in
                                           ('invocation.json', 'source-before.json', 'flutter.log')}
        intent = {key: self.jcertificate[key] for key in (
            'runId', 'device', 'package', 'pid', 'operationSourceSha256', 'beforeStop', 'priorClosedRun',
            'boundFiles', 'appConfigSha256', 'consumerConfigSha256', 'operation', 'hostDriver',
            'installationFailure', 'serviceHealthBefore', 'priorStoppedRun', 'appStopRequested', 'zeroResumeAttempts')}
        self.write(self.joutput / 'pre-test-recovery-intent.json', intent)
        self.jcertificate['recoveryIntentSha256'] = RUNNER.digest(self.joutput / 'pre-test-recovery-intent.json')
        self.write(self.joutput / 'pre-test-preservation.json', self.jcertificate)
        self.write(self.joutput / 'result.json', self.jreport)
        self.jpins['certificateSha256'] = RUNNER.digest(self.joutput / 'pre-test-preservation.json')
        self.jpins['resultSha256'] = RUNNER.digest(self.joutput / 'result.json')

    def test_both_exact_admissions_are_explicit_and_preserve_distinct_closure_facts(self):
        self.add_install_failure_case()
        with patch.object(RUNNER.subprocess, 'Popen') as launch:
            admissions = RUNNER.assert_prior_device_preserved(self.device, [self.run, self.jrun])
        launch.assert_not_called()
        self.assertEqual([item['runId'] for item in admissions], [self.run, self.jrun])
        self.assertTrue(all(item['nativeDisposedObserved'] is False for item in admissions))
        self.assertFalse(any(RUNNER.known_pretest_admission_changed(item) for item in admissions))
        self.assertEqual(json.loads((self.joutput / 'result.json').read_text())['status'], 'failed')
        self.assertFalse((self.joutput / 'preservation.json').exists())

    def test_one_flag_duplicate_or_unknown_case_never_implicitly_admits_the_other(self):
        self.add_install_failure_case()
        for requested in ([self.run], [self.jrun], [self.run, self.run], [self.run, 'unknown-launch']):
            with self.subTest(requested=requested), self.assertRaises(RuntimeError):
                RUNNER.assert_prior_device_preserved(self.device, requested)

    def test_install_failure_must_never_have_started_app(self):
        self.add_install_failure_case()
        self.jcertificate['beforeStop']['process']['packagePids'] = [1234]
        self.save_install_failure_case()
        with self.assertRaises(RuntimeError):
            RUNNER.known_pretest_failure_admission(self.device, self.jrun)
        self.jcertificate['beforeStop']['process']['packagePids'] = []
        self.jcertificate['pid'] = 1234
        self.save_install_failure_case()
        with self.assertRaises(RuntimeError):
            RUNNER.known_pretest_failure_admission(self.device, self.jrun)

    def test_install_failure_has_zero_resume_files_before_and_after_admission(self):
        self.add_install_failure_case()
        admission = RUNNER.known_pretest_failure_admission(self.device, self.jrun)
        (self.joutput / 'targeted-resume-intent.json').write_text('{}')
        self.assertTrue(RUNNER.known_pretest_admission_changed(admission))
        with self.assertRaises(RuntimeError):
            RUNNER.known_pretest_failure_admission(self.device, self.jrun)
        (self.joutput / 'targeted-resume-intent.json').unlink()
        self.jcertificate['zeroResumeAttempts'] = False
        self.save_install_failure_case()
        with self.assertRaises(RuntimeError):
            RUNNER.known_pretest_failure_admission(self.device, self.jrun)

    def test_install_failure_driver_must_not_have_connected(self):
        self.add_install_failure_case()
        self.jcertificate['installationFailure']['driverConnected'] = True
        self.save_install_failure_case()
        with self.assertRaises(RuntimeError):
            RUNNER.known_pretest_failure_admission(self.device, self.jrun)
        self.jcertificate['installationFailure']['driverConnected'] = False
        self.jcertificate['installationFailure']['errorCount'] = 2
        self.save_install_failure_case()
        with self.assertRaises(RuntimeError):
            RUNNER.known_pretest_failure_admission(self.device, self.jrun)

    def test_install_failure_original_i_reference_cannot_be_redefined(self):
        self.add_install_failure_case()
        self.jcertificate['priorStoppedRun']['archiveSha256'] = '0' * 64
        self.save_install_failure_case()
        with self.assertRaises(RuntimeError):
            RUNNER.known_pretest_failure_admission(self.device, self.jrun)

    def test_install_failure_rejects_any_late_event_or_failed_report_byte_drift(self):
        self.add_install_failure_case()
        admission = RUNNER.known_pretest_failure_admission(self.device, self.jrun)
        (self.evidence / 'events.jsonl').write_text(json.dumps({'run_id': self.jrun, 'event': 'test_started'})+'\n')
        self.assertTrue(RUNNER.known_pretest_admission_changed(admission))
        (self.evidence / 'events.jsonl').unlink()
        (self.joutput / 'result.json').write_text('{}')
        self.assertTrue(RUNNER.known_pretest_admission_changed(admission))
        with self.assertRaises(RuntimeError):
            RUNNER.known_pretest_failure_admission(self.device, self.jrun)

    def test_install_failure_still_requires_unchanged_wallet_production_source(self):
        self.add_install_failure_case()
        self.app_identity['files']['lib/app.dart'] = '0' * 64
        with self.assertRaises(RuntimeError):
            RUNNER.known_pretest_failure_admission(self.device, self.jrun)


    def test_j_report_must_retain_unchanged_original_i_admission(self):
        self.add_install_failure_case()
        self.jreport['priorLaunchEvidenceChangedDuringRun'] = True
        self.save_install_failure_case()
        with self.assertRaises(RuntimeError):
            RUNNER.known_pretest_failure_admission(self.device, self.jrun)
        self.jreport['priorLaunchEvidenceChangedDuringRun'] = False
        self.jreport['priorLaunchAdmission']['archive']['sha256'] = '0' * 64
        self.save_install_failure_case()
        with self.assertRaises(RuntimeError):
            RUNNER.known_pretest_failure_admission(self.device, self.jrun)


class AndroidFrameworkHealthTests(unittest.TestCase):
    def test_exact_healthy_responses_are_required(self):
        self.assertEqual(RUNNER.parse_android_framework_health(
            '1\r\n', 'Service package: found\n', 'Service activity: found\n'),
            {'bootCompleted': True, 'packageServiceFound': True, 'activityServiceFound': True})
        for values in [('0', 'Service package: found', 'Service activity: found'),
                       ('1', 'Service package: not found', 'Service activity: found'),
                       ('1', 'Service package: found', 'Service activity: not found'),
                       ('1', 'found', 'Service activity: found')]:
            with self.subTest(values=values), self.assertRaises(RuntimeError):
                RUNNER.parse_android_framework_health(*values)

    def test_readonly_commands_are_owned_and_success_exit_is_not_enough(self):
        with patch.object(RUNNER.subprocess, 'run', side_effect=[
            SimpleNamespace(returncode=0, stdout='1'),
            SimpleNamespace(returncode=0, stdout='Service package: not found'),
            SimpleNamespace(returncode=0, stdout='Service activity: not found')]) as command:
            with self.assertRaises(RuntimeError):
                RUNNER.android_framework_preflight('emulator-5582')
        self.assertEqual([call.args[0][1:] for call in command.call_args_list], [
            ['-s', 'emulator-5582', 'shell', 'getprop', 'sys.boot_completed'],
            ['-s', 'emulator-5582', 'shell', 'service', 'check', 'package'],
            ['-s', 'emulator-5582', 'shell', 'service', 'check', 'activity']])
        for call in command.call_args_list:
            self.assertEqual(call.kwargs['timeout'], 10)

    def test_failed_command_and_other_platform_never_launch(self):
        with patch.object(RUNNER.subprocess, 'run', return_value=SimpleNamespace(returncode=1)) as command:
            with self.assertRaises(RuntimeError):
                RUNNER.android_framework_preflight('emulator-5582')
            self.assertEqual(command.call_count, 1)
        with patch.object(RUNNER.subprocess, 'run') as command:
            self.assertIsNone(RUNNER.android_framework_preflight('857A20C2-601C-4864-AFEB-B525D1B5B4D7'))
            command.assert_not_called()


if __name__ == '__main__':
    unittest.main()
