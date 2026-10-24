#!/usr/bin/env python3
"""Qualify Aster using existing shared services, never provision infrastructure.

The separately operated loopback controller owns funding and bridge mutation
journals. This runner launches one unique app fixture and preserves its closed
files before acknowledging teardown. It never retries financial operations.
Simulator Keychain records stay on the same simulator; this is a local test
snapshot, not a portable recovery backup.
"""

import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time
import urllib.request
from urllib.parse import urljoin, urlsplit


ROOT = Path(__file__).resolve().parents[1]
SHARED = Path(os.environ.get('ASTER_SHARED_STACK', ROOT.parent.parent / 'utexo-local-stack'))
EVIDENCE = ROOT / '.buildlog/full-wallet-20261015'
PACKAGE = 'com.example.asterdev.debug'
RUN_ID_PATTERN = r'[A-Za-z0-9][A-Za-z0-9_-]{2,63}'
DEVICE_PATTERN = r'(?:emulator-[0-9]+|[A-F0-9-]{36})'
SDK_REPOSITORY = 'https://github.com/zeusbuilds/rgb-sdk-flutter.git'
RECONCILIATION_SOURCE_CHANGES = frozenset({
    'docs/PRODUCTION_REFACTOR_TRACKER.md', 'docs/REGTEST.md',
    'docs/SHARED_WALLET_QUALIFICATION.md', 'integration_test/full_wallet_flow_test.dart',
    'integration_test/support/full_wallet_qa.dart',
    'test/integration/full_wallet_qa_public_fields_test.dart',
    'test/tool/shared_wallet_qualification_runner_test.py',
    'tool/run_shared_wallet_qualification.py',
})
TRANSFER_RECONCILIATION_RUN = 'aster-full-ios27-20261015-g'
TRANSFER_RECONCILIATION_CHECKPOINT = 'aster-reconcile-transfer-ios27-20261015-a'
TRANSFER_RECONCILIATION_CHECKPOINT_MANIFEST = 'c7e323ffc1cbdbd1c98831be4cbdc8c14be7e96c670bf0846dbc00836dc6542a'
TRANSFER_RECONCILIATION_CHECKPOINT_REPORT = 'db032da6fd3bc8b23058e9fba14ef73cde1e48497d7735bbbc261196b9693148'
TRANSFER_RECONCILIATION_EVENTS_SHA256 = '97eb90544614085962898f84aecb381d29bfe305ecf039e6d4ada5ce49dd2811'
TRANSFER_RECONCILIATION_SOURCE_CHANGES = RECONCILIATION_SOURCE_CHANGES | frozenset({
    'integration_test/support/full_wallet_import_transfer.dart',
    'integration_test/support/full_wallet_rgb_setup.dart',
    'integration_test/support/full_wallet_send_ui.dart',
    'integration_test/support/full_wallet_test_guard.dart',
    'test/integration/full_wallet_import_harness_test.dart',
})


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tree_digest(root):
    if root.is_symlink():
        raise RuntimeError('Linked wallet snapshot refused')
    records = {}
    for path in sorted(root.rglob('*')):
        if path.is_symlink():
            raise RuntimeError('Linked wallet snapshot refused')
        if path.is_file():
            records[str(path.relative_to(root))] = digest(path)
    return hashlib.sha256(json.dumps(records, sort_keys=True).encode()).hexdigest()


def sync_directory(path):
    descriptor = os.open(path, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def write_durable_json(path, value):
    with path.open('x') as stream:
        json.dump(value, stream, indent=2)
        stream.write('\n')
        stream.flush()
        os.fsync(stream.fileno())
    sync_directory(path.parent)


@contextmanager
def device_lock(device):
    """Hold one host runner owner through launch, preservation and reporting."""
    if not re.fullmatch(DEVICE_PATTERN, device):
        raise RuntimeError('Invalid device lock identity')
    directory = EVIDENCE / '.runner-locks'
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    if directory.is_symlink():
        raise RuntimeError('Linked runner lock directory refused')
    descriptor = os.open(directory / (device + '.lock'),
                         os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RuntimeError('Another qualification runner owns this device') from error
        yield
    finally:
        os.close(descriptor)


def verify_closed_backup(output, device, backup):
    """Validate retained bytes, independently of test or runner success."""
    if (not isinstance(backup, dict) or backup.get('status') != 'saved'
            or backup.get('nativeClosed') is not True):
        raise RuntimeError('Prior native owner has no verified closed backup')
    if device.startswith('emulator-'):
        archive = output / 'private-device-state.tar'
        size = backup.get('bytes')
        expected = backup.get('sha256')
        if (archive.is_symlink() or not archive.is_file()
                or type(size) is not int or size <= 0 or archive.stat().st_size != size
                or not isinstance(expected, str) or not re.fullmatch(r'[a-f0-9]{64}', expected)
                or digest(archive) != expected):
            raise RuntimeError('Closed Android snapshot hash or size differs')
    else:
        snapshot = output / 'private-device-state'
        expected = backup.get('filesManifestSha256')
        if (snapshot.is_symlink() or not snapshot.is_dir()
                or not isinstance(expected, str) or not re.fullmatch(r'[a-f0-9]{64}', expected)
                or tree_digest(snapshot) != expected):
            raise RuntimeError('Closed iOS snapshot content hash differs')


# Exact reviewed pretest failures; no case asserts native disposal.
KNOWN_PRETEST_FAILURES = {
    'aster-full-android17-20261015-i': {
        'runId': 'aster-full-android17-20261015-i', 'device': 'emulator-5582',
        'certificateSha256': '470335619f27a17c3981a5b943b7ba3e50a923b611fcc6e876c4deeceb390843',
        'resultSha256': '4258ff0919212697a1e128cf20960d2a0980a1174eeb77cdb17d1ae64edb2f55',
        'archiveSha256': 'fdd5dcf152ebbc450b2981f19427e437fa091a51ab10d45b6adb1a65f795a741',
        'archiveBytes': 148838912,
        'priorRunId': 'aster-full-android17-20261015-h',
        'priorArchiveSha256': '3256dd79c032ccf94183bfd0d1e55bc30a60ac44bf55b817df7229c4f5bcb1ad',
        'priorArchiveBytes': 695808,
        'priorRegularFiles': 29,
        'priorRecordsSha256': '40472e4430c30cf6ba5251f177edb3ab24889be540a43fbeb829ecc7410fda46',
        'closureBasis': 'host-stopped-before-qa-storage-creation',
        'operation': 'force-stop-exact-pretest-package-and-preserve',
        'resumeMode': 'one-uncertain-resume',
        'driverExitBasis': 'exited-after-app-disconnect-no-host-signal-sent',
    },
    'aster-full-android17-20261015-j': {
        'runId': 'aster-full-android17-20261015-j', 'device': 'emulator-5582',
        'certificateSha256': 'd17fa38c5e2b193770b87dc68c36affdbf98844d4ee307d05687f2c9e94a6ed3',
        'resultSha256': '573faf2b5049ffe180452add98f17dcb946e7523bb3186fb52e847902fe2e58c',
        'archiveSha256': 'fdd5dcf152ebbc450b2981f19427e437fa091a51ab10d45b6adb1a65f795a741',
        'archiveBytes': 148838912,
        'priorRunId': 'aster-full-android17-20261015-h',
        'priorArchiveSha256': '3256dd79c032ccf94183bfd0d1e55bc30a60ac44bf55b817df7229c4f5bcb1ad',
        'priorArchiveBytes': 695808, 'priorRegularFiles': 29,
        'priorRecordsSha256': '40472e4430c30cf6ba5251f177edb3ab24889be540a43fbeb829ecc7410fda46',
        'closureBasis': 'install-failed-before-app-start',
        'operation': 'preserve-prelaunch-install-failure',
        'resumeMode': 'none', 'priorPretestRun': 'aster-full-android17-20261015-i',
        'driverExitBasis': 'exited-after-installation-failed-no-app-start',
        'packageServiceFailureCount': 3,
    },
}

PRETEST_ADMISSION_SOURCE_CHANGES = frozenset({
    'tool/run_shared_wallet_qualification.py',
    'test/tool/shared_wallet_qualification_runner_test.py',
    'docs/REGTEST.md', 'docs/SHARED_WALLET_QUALIFICATION.md',
    'docs/PRODUCTION_REFACTOR_TRACKER.md',
})


def known_pretest_failure_admission(device, run_id):
    """Admit a pinned failed launch that never created QA wallet storage.

    This is not a native shutdown acknowledgement or a passed qualification.
    All wallet-owning launches still require their actual closed native backup.
    """
    pins = KNOWN_PRETEST_FAILURES.get(run_id)
    if (pins is None or device != pins['device']
            or not isinstance(pins['resultSha256'], str)
            or not re.fullmatch(r'[a-f0-9]{64}', pins['resultSha256'])):
        raise RuntimeError('Only an explicitly pinned failed Android pretest launch may be admitted')
    output = EVIDENCE / run_id
    resume_names = ('targeted-resume-intent.json', 'targeted-resume-result.json')
    names = ('result.json', 'source-before.json', 'invocation.json', 'flutter.log',
             'pre-test-preservation.json', 'pre-test-recovery-intent.json')
    if pins['resumeMode'] == 'one-uncertain-resume':
        names += resume_names
    elif pins['resumeMode'] != 'none' or any((output / name).exists() for name in resume_names):
        raise RuntimeError('Unpermitted pretest resume evidence')
    if output.is_symlink() or any((output / name).is_symlink() for name in names):
        raise RuntimeError('Linked pretest evidence refused')
    bound = {name: digest(output / name) for name in names}
    if (bound['pre-test-preservation.json'] != pins['certificateSha256']
            or bound['result.json'] != pins['resultSha256']):
        raise RuntimeError('Known failed pretest certificate or report hash differs')
    report = json.loads((output / 'result.json').read_text())
    if (report.get('schemaVersion') != 1 or report.get('runId') != run_id
            or report.get('device') != device or report.get('stage') != 'full'
            or report.get('status') != 'failed' or type(report.get('exitCode')) is not int
            or report['exitCode'] == 0 or report.get('runnerError') is not None
            or report.get('events') != [] or read_events(run_id) != []
            or report.get('privateFixtureBackup') != {'status': 'unavailable'}
            or report.get('flutterLogSha256') != bound['flutter.log']
            or any(report.get(key) is not False for key in (
                'appSourceChangedDuringRun', 'sdkSourceChangedDuringRun',
                'configurationChangedDuringRun', 'infrastructureStarted', 'containersCreated', 'stateReset'))
            or (output / 'preservation.json').exists()):
        raise RuntimeError('Pretest launch entered a test or lacks its original failed outcome')
    invocation = json.loads((output / 'invocation.json').read_text())
    if invocation != {'schemaVersion': 1, 'runId': run_id, 'device': device,
                      'package': PACKAGE, 'stage': 'full', 'storageRunId': run_id}:
        raise RuntimeError('Pretest invocation owner differs')
    certificate = json.loads((output / 'pre-test-preservation.json').read_text())
    intent = json.loads((output / 'pre-test-recovery-intent.json').read_text())
    manifest = json.loads((output / 'source-before.json').read_text())
    if (certificate.get('schemaVersion') != 1 or certificate.get('runId') != run_id
            or certificate.get('device') != device or certificate.get('package') != PACKAGE
            or certificate.get('closureBasis') != pins['closureBasis']
            or certificate.get('nativeDisposedObserved') is not False
            or any(certificate.get(key) is not False for key in (
                'normalDisposalAcknowledgementWritten', 'normalPreservationWritten',
                'infrastructureStarted', 'containersCreated', 'stateReset'))
            or certificate.get('normalResultUntouched') is not True
            or certificate.get('sourceMatchesLaunchManifestBeforeAndAfter') is not True
            or certificate.get('recoveryIntentSha256') != bound['pre-test-recovery-intent.json']
            or any(certificate.get('boundFiles', {}).get(name) != bound[name] for name in (
                ('invocation.json', 'source-before.json', *resume_names)
                if pins['resumeMode'] == 'one-uncertain-resume' else
                ('invocation.json', 'source-before.json', 'flutter.log')))
            or intent.get('boundFiles') != certificate.get('boundFiles')
            or intent.get('operation') != pins['operation']
            or any(intent.get(key) != certificate.get(key) for key in (
                'runId', 'device', 'package', 'pid', 'operationSourceSha256', 'beforeStop', 'priorClosedRun'))):
        raise RuntimeError('Pretest host preservation certificate differs')
    pid = certificate.get('pid')
    had_process = pins['resumeMode'] == 'one-uncertain-resume'
    if ((had_process and (type(pid) is not int or pid <= 0
                         or certificate['beforeStop']['process'].get('pid') != pid))
            or (not had_process and pid is not None)):
        raise RuntimeError('Pretest owned process identity differs')
    expected_root = '/data/user/0/' + PACKAGE + '/files/aster_full_wallet_qa/' + run_id
    for phase in ('beforeStop', 'afterStop', 'afterQuiescence', 'afterArchive'):
        observation = certificate.get(phase, {})
        events = observation.get('events', {})
        fixture = observation.get('fixture', {})
        if (type(events.get('runEventCount')) is not int or events['runEventCount'] != 0
                or fixture.get('absent') is not True or fixture.get('path') != expected_root):
            raise RuntimeError('Pretest namespace or event absence is not established')
        if phase != 'beforeStop' or not had_process:
            process = observation.get('process', {})
            if process.get('expectedPidAbsent') is not True or process.get('packagePids') != []:
                raise RuntimeError('Pretest app process remains active')
    driver = certificate.get('hostDriver', {})
    timing = certificate.get('stopTiming', {})
    intent_driver = ({'pid': intent.get('hostFlutterDrivePid'),
                      'coordinatorPid': intent.get('coordinatorPid')} if had_process
                     else intent.get('hostDriver', {}))
    if (driver.get('absentAfter') is not True
            or (had_process and (type(driver.get('pid')) is not int or driver['pid'] <= 0))
            or (not had_process and (driver.get('pid') is not None
                or driver.get('originalDriverPidNotCaptured') is not True
                or driver.get('matchingDriveProcesses') != []))
            or driver.get('pid') != intent_driver.get('pid')
            or driver.get('coordinatorPid') != intent_driver.get('coordinatorPid')
            or driver.get('coordinatorStopRequested') is not False
            or driver.get('termSent') is not False
            or driver.get('exitBasis') != pins['driverExitBasis']
            or (had_process and timing.get('requestSentOnce') is not True)):
        raise RuntimeError('Pretest app/driver stop evidence differs')
    resume_intent = None
    if had_process:
        resume_intent = json.loads((output / 'targeted-resume-intent.json').read_text())
        resumed = json.loads((output / 'targeted-resume-result.json').read_text())
        if (resume_intent.get('operation') != 'VMService.resume'
                or resume_intent.get('endpointClass') != 'existing-native-ADB-forward'
                or resume_intent.get('currentAppAndSdkExactlyMatchLaunchManifest') is not True
                or resume_intent.get('zeroRunEvents') is not True
                or type(resume_intent.get('runEventCountBefore')) is not int or resume_intent['runEventCountBefore'] != 0
                or type(resume_intent.get('maxAttempts')) is not int or resume_intent['maxAttempts'] != 1
                or type(resume_intent.get('timeoutSeconds')) is not int or resume_intent['timeoutSeconds'] != 5
                or resumed.get('intentSha256') != bound['targeted-resume-intent.json']
                or type(resumed.get('attemptCount')) is not int or resumed['attemptCount'] != 1
                or resumed.get('status') != 'outcome_uncertain_no_retry' or resumed.get('retryPermitted') is not False
                or not isinstance(resume_intent.get('isolateId'), str)
                or resumed.get('isolateId') != resume_intent['isolateId']
                or any(value.get('runId') != run_id or value.get('device') != device
                       or value.get('pid') != pid for value in (resume_intent, resumed))):
            raise RuntimeError('Pretest one uncertain resume receipt differs')
    elif (certificate.get('zeroResumeAttempts') is not True
          or certificate.get('appStopRequested') is not False
          or intent.get('zeroResumeAttempts') is not True or intent.get('appStopRequested') is not False
          or certificate.get('installationFailure') != {
              'buildSucceeded': True, 'driverConnected': False,
              'error': "Can't find service: package", 'errorCount': pins['packageServiceFailureCount']}
          or certificate.get('serviceHealthBefore') != {
              'activity': 'Service activity: not found', 'package': 'Service package: not found'}
          or certificate.get('priorStoppedRun') != {
              'runId': pins['priorPretestRun'],
              'certificateSha256': KNOWN_PRETEST_FAILURES[pins['priorPretestRun']]['certificateSha256'],
              'failedResultSha256': KNOWN_PRETEST_FAILURES[pins['priorPretestRun']]['resultSha256'],
              'archiveSha256': KNOWN_PRETEST_FAILURES[pins['priorPretestRun']]['archiveSha256'],
              'archiveBytes': KNOWN_PRETEST_FAILURES[pins['priorPretestRun']]['archiveBytes']}
          or any(intent.get(key) != certificate.get(key) for key in (
              'installationFailure', 'serviceHealthBefore', 'priorStoppedRun'))
          or (output / 'flutter.log').read_text().count(
              "cmd: Can't find service: package") != pins['packageServiceFailureCount']):
        raise RuntimeError('Install-failed pretest entered an app or attempted a resume')
    prior_stopped_admission = None
    if pins['resumeMode'] == 'none':
        prior_stopped_admission = known_pretest_failure_admission(device, pins['priorPretestRun'])
        original_admission = {key: value for key, value in prior_stopped_admission.items() if key != 'device'}
        if (report.get('priorLaunchAdmission') != original_admission
                or report.get('priorLaunchEvidenceChangedDuringRun') is not False):
            raise RuntimeError('Install-failed launch no longer binds the original stopped-launch evidence')
    sdk_dependency = resolved_sdk_dependency()
    sdk_identity = source_identity(Path(sdk_dependency['root']))
    app_identity = source_identity(ROOT)
    config_sha = digest(ROOT / 'config/shared-stack.android.local.json')
    consumer_sha = digest(SHARED / 'artifacts/consumer-config.json')
    old_files = manifest.get('app', {}).get('files')
    if (not isinstance(old_files, dict) or manifest.get('sdk') != sdk_identity
            or manifest.get('sdkDependency') != sdk_dependency
            or report.get('sdkDependencyBefore') != sdk_dependency or report.get('sdkDependencyAfter') != sdk_dependency
            or certificate.get('appFilesSha256') != manifest.get('app', {}).get('filesSha256')
            or certificate.get('sdkFilesSha256') != sdk_identity.get('filesSha256')
            or (resume_intent is not None and
                resume_intent.get('sourceManifestSha256') != bound['source-before.json'])
            or any(value.get('appConfigSha256') != config_sha or value.get('consumerConfigSha256') != consumer_sha
                   for value in (certificate, intent, manifest))
            or report.get('appConfigSha256') != config_sha or report.get('appConfigSha256AtEnd') != config_sha
            or report.get('consumerConfigSha256') != consumer_sha or report.get('consumerConfigSha256AtEnd') != consumer_sha
            or not {name for name in set(old_files) | set(app_identity['files'])
                    if old_files.get(name) != app_identity['files'].get(name)}.issubset(PRETEST_ADMISSION_SOURCE_CHANGES)):
        raise RuntimeError('Pretest production source, SDK or configuration differs')
    prior = certificate.get('priorClosedRun', {})
    if (prior.get('runId') != pins['priorRunId'] or prior.get('archiveSha256') != pins['priorArchiveSha256']
            or type(prior.get('archiveBytes')) is not int or prior['archiveBytes'] != pins['priorArchiveBytes']
            or type(certificate.get('priorFixtureRegularFiles', {}).get('count')) is not int
            or certificate.get('priorFixtureRegularFiles', {}).get('equal') is not True
            or certificate.get('priorFixtureRegularFiles') != {'count': pins['priorRegularFiles'],
                'equal': True, 'recordsSha256': pins['priorRecordsSha256']}):
        raise RuntimeError('Prior H funded fixture preservation differs')
    prior_output = EVIDENCE / pins['priorRunId']
    if prior_output.is_symlink():
        raise RuntimeError('Linked prior H fixture refused')
    for name, expected in prior.get('boundFiles', {}).items():
        if name not in {'result.json', 'source-before.json', 'invocation.json', 'preservation.json'}:
            raise RuntimeError('Unknown prior H evidence path')
        path = prior_output / name
        if path.is_symlink() or digest(path) != expected:
            raise RuntimeError('Prior H evidence changed')
    if set(prior.get('boundFiles', {})) != {'result.json', 'source-before.json', 'invocation.json', 'preservation.json'}:
        raise RuntimeError('Prior H evidence binding is incomplete')
    prior_backup = json.loads((prior_output / 'preservation.json').read_text()).get('backup')
    verify_closed_backup(prior_output, device, prior_backup)
    if prior_backup.get('sha256') != pins['priorArchiveSha256'] or prior_backup.get('bytes') != pins['priorArchiveBytes']:
        raise RuntimeError('Prior H closed archive differs')
    archive = certificate.get('archive', {})
    if (archive.get('name') != 'pre-test-private-app-data.tar'
            or type(archive.get('bytes')) is not int or archive['bytes'] != pins['archiveBytes']
            or archive.get('sha256') != pins['archiveSha256']
            or archive.get('roots') != ['/data/user/0/' + PACKAGE, '/data/user_de/0/' + PACKAGE]
            or archive.get('mode') != '0600' or archive.get('outputDirectoryMode') != '0700'):
        raise RuntimeError('Complete private app-data archive metadata differs')
    evidence = {'runId': run_id, 'device': device, 'closureBasis': certificate['closureBasis'],
                'nativeDisposedObserved': False, 'boundFiles': bound, 'archive': archive,
                'priorClosedRun': prior, 'originalReportRemainsFailed': True}
    if prior_stopped_admission is not None:
        evidence['priorStoppedAdmission'] = prior_stopped_admission
    if known_pretest_admission_changed(evidence):
        raise RuntimeError('Pinned pretest preservation changed before admission')
    return evidence


def known_pretest_admission_changed(evidence):
    if evidence is None:
        return False
    try:
        output = EVIDENCE / evidence['runId']
        pins = KNOWN_PRETEST_FAILURES[evidence['runId']]
        if known_pretest_admission_changed(evidence.get('priorStoppedAdmission')):
            return True
        if (output.is_symlink() or read_events(evidence['runId']) != []
                or (pins['resumeMode'] == 'none' and any((output / name).exists() for name in (
                    'targeted-resume-intent.json', 'targeted-resume-result.json')))
                or (output / 'preservation.json').exists()
                or any((output / name).is_symlink() or digest(output / name) != expected
                       for name, expected in evidence['boundFiles'].items())):
            return True
        archive = output / evidence['archive']['name']
        if (archive.is_symlink() or archive.stat().st_size != evidence['archive']['bytes']
                or (archive.stat().st_mode & 0o777) != 0o600
                or (output.stat().st_mode & 0o777) != 0o700
                or digest(archive) != evidence['archive']['sha256']):
            return True
        prior = evidence['priorClosedRun']
        prior_output = EVIDENCE / prior['runId']
        if (prior_output.is_symlink()
                or any((prior_output / name).is_symlink() or digest(prior_output / name) != expected
                       for name, expected in prior['boundFiles'].items())):
            return True
        verify_closed_backup(prior_output, evidence['device'], {
            'status': 'saved', 'nativeClosed': True,
            'sha256': prior['archiveSha256'], 'bytes': prior['archiveBytes']})
        return False
    except (OSError, ValueError, KeyError, TypeError, AttributeError, RuntimeError):
        return True


def assert_prior_device_preserved(device, admit_pretest_failures=None):
    """Never reinstall over an unpreserved fixture from a prior invocation.

    Old reports created before invocation receipts were introduced stay as
    historical evidence. Every new invocation must have a matching durable
    preservation receipt, even when its financial test itself failed.
    """
    requested = [] if admit_pretest_failures is None else admit_pretest_failures
    if (not isinstance(requested, list) or any(not isinstance(run, str) for run in requested)
            or len(requested) != len(set(requested))):
        raise RuntimeError('Pretest admissions must name unique explicit launch IDs')
    admissions = [known_pretest_failure_admission(device, run) for run in requested]
    admitted_runs = {evidence['runId'] for evidence in admissions}
    for receipt_path in sorted(EVIDENCE.glob('*/invocation.json')):
        output = receipt_path.parent
        try:
            if output.is_symlink() or receipt_path.is_symlink():
                raise ValueError('Linked invocation receipt')
            receipt = json.loads(receipt_path.read_text())
            if (receipt.get('schemaVersion') != 1 or receipt.get('package') != PACKAGE
                    or receipt.get('runId') != output.name
                    or not re.fullmatch(RUN_ID_PATTERN, output.name)
                    or receipt.get('stage') not in ('lifecycle', 'full', 'restore', 'reconcile-mint', 'reconcile-transfer')
                    or not isinstance(receipt.get('storageRunId'), str)
                    or not re.fullmatch(RUN_ID_PATTERN, receipt['storageRunId'])
                    or not isinstance(receipt.get('device'), str)
                    or not re.fullmatch(DEVICE_PATTERN, receipt['device'])):
                raise ValueError('Invalid invocation receipt')
            if receipt['device'] != device:
                continue
            if output.name in admitted_runs:
                continue
            proof_path = output / 'preservation.json'
            if proof_path.is_symlink():
                raise ValueError('Linked preservation receipt')
            proof = json.loads(proof_path.read_text())
            if (proof.get('schemaVersion') != 1 or proof.get('device') != device
                    or proof.get('runId') != receipt['runId']
                    or proof.get('package') != PACKAGE
                    or proof.get('storageRunId') != receipt.get('storageRunId')):
                raise ValueError('Preservation owner mismatch')
            verify_closed_backup(output, device, proof.get('backup'))
        except (OSError, ValueError, TypeError, AttributeError, RuntimeError) as error:
            raise RuntimeError(
                'Prior qualification fixture is not safely preserved; inspect ' + str(output)
            ) from error

    return admissions


def record_preservation(output, args, backup):
    verify_closed_backup(output, args.device, backup)
    write_durable_json(output / 'preservation.json', {
        'schemaVersion': 1, 'runId': args.run_id, 'device': args.device,
        'package': PACKAGE, 'storageRunId': args.restore_from or args.run_id,
        'backup': backup,
    })


def preserve_and_ack(event, args, output):
    backup = preserve(event, args, output)
    record_preservation(output, args, backup)
    write_ack(event['id'], {'backup_verified': True})
    return backup


def qualification_passed(code, passed, disposed, backup, runner_error, source_changed):
    return (code == 0 and passed and disposed and backup.get('status') == 'saved'
            and backup.get('nativeClosed') is True
            and runner_error is None and not source_changed)


def coordinate_driver_exit(process, service_events, grace_seconds=360):
    """Serve native teardown after a lost driver without changing its outcome.

    Flutter's host driver can disconnect while the native app still owns its
    wallet. Its bounded five-minute operation wait and finally block must retain
    a host that can preserve closed files and acknowledge the backup. The grace
    only coordinates existing events; it never restarts or terminates the app.
    """
    exit_deadline = None
    while True:
        if process.poll() is not None and exit_deadline is None:
            exit_deadline = time.monotonic() + grace_seconds
        closed_and_preserved = service_events()
        if exit_deadline is not None and (
                closed_and_preserved or time.monotonic() >= exit_deadline):
            return process.wait()
        time.sleep(0.25)


def sync_private_tree(root):
    records = {}
    for current, directories, files in os.walk(root, topdown=False, followlinks=False):
        for name in directories + files:
            if (Path(current) / name).is_symlink():
                raise RuntimeError('Linked wallet snapshot refused')
        for name in files:
            path = Path(current) / name
            path.chmod(0o600)
            with path.open('rb') as stream:
                os.fsync(stream.fileno())
            records[str(path.relative_to(root))] = digest(path)
        Path(current).chmod(0o700)
        sync_directory(current)
    return hashlib.sha256(json.dumps(records, sort_keys=True).encode()).hexdigest()


def source_identity(root):
    names = subprocess.check_output(
        ['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'],
        cwd=root,
    ).split(b'\0')
    records = {}
    for raw in sorted(set(names)):
        if not raw:
            continue
        name = os.fsdecode(raw)
        path = root / name
        if path.is_file():
            records[name] = digest(path)
    encoded = json.dumps(records, sort_keys=True, separators=(',', ':')).encode()
    return {
        'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
        'filesSha256': hashlib.sha256(encoded).hexdigest(),
        'files': records,
    }


def yaml_block(text, key, indent):
    """Read one canonical Pub YAML block, rejecting ambiguous layouts."""
    lines = text.splitlines()
    matches = [index for index, line in enumerate(lines)
               if re.fullmatch(' ' * indent + re.escape(key) + r':\s*(?:#.*)?', line)]
    if len(matches) != 1:
        raise RuntimeError('Missing or ambiguous dependency YAML block: ' + key)
    start = matches[0] + 1
    end = start
    while end < len(lines):
        line = lines[end]
        if line.strip() and not line.lstrip().startswith('#'):
            if '\t' in line[:len(line) - len(line.lstrip())]:
                raise RuntimeError('Noncanonical dependency indentation')
            if len(line) - len(line.lstrip()) <= indent:
                break
        end += 1
    return '\n'.join(lines[start:end])


def yaml_scalar(block, key, indent):
    values = re.findall('^' + ' ' * indent + re.escape(key) + r':\s*(.+?)\s*$', block, re.M)
    if len(values) != 1:
        raise RuntimeError('Missing or ambiguous dependency scalar: ' + key)
    value = values[0]
    if value.startswith('"'):
        try:
            value = json.loads(value)
        except ValueError as error:
            raise RuntimeError('Invalid quoted dependency scalar') from error
    elif value.startswith("'"):
        if not value.endswith("'"):
            raise RuntimeError('Invalid quoted dependency scalar')
        value = value[1:-1].replace("''", "'")
    if not isinstance(value, str):
        raise RuntimeError('Dependency scalar must be text')
    return value


def resolved_sdk_dependency():
    """Bind --no-pub builds to the actual immutable Git package they consume."""
    override = ROOT / 'pubspec_overrides.yaml'
    if override.exists() or override.is_symlink():
        raise RuntimeError('Qualification requires no pubspec_overrides.yaml')
    pubspec = (ROOT / 'pubspec.yaml').read_text()
    if re.search(r'^dependency_overrides\s*:', pubspec, re.M):
        overrides = yaml_block(pubspec, 'dependency_overrides', 0)
        if re.search(r'^  rgb_sdk_flutter\s*:', overrides, re.M):
            raise RuntimeError('SDK dependency override refused')
    dependency = yaml_block(yaml_block(pubspec, 'dependencies', 0), 'rgb_sdk_flutter', 2)
    git = yaml_block(dependency, 'git', 4)
    requested = yaml_scalar(git, 'ref', 6)
    repository = yaml_scalar(git, 'url', 6)
    if not re.fullmatch(r'[a-f0-9]{40}', requested) or repository != SDK_REPOSITORY:
        raise RuntimeError('SDK requires the canonical repository and full immutable Git ref')
    lock = yaml_block(yaml_block((ROOT / 'pubspec.lock').read_text(), 'packages', 0),
                      'rgb_sdk_flutter', 2)
    description = yaml_block(lock, 'description', 4)
    if (yaml_scalar(lock, 'source', 4) != 'git'
            or yaml_scalar(description, 'path', 6) != '.'
            or yaml_scalar(description, 'url', 6) != repository
            or yaml_scalar(description, 'ref', 6) != requested
            or yaml_scalar(description, 'resolved-ref', 6) != requested):
        raise RuntimeError('SDK lock does not match its immutable Git dependency')
    config_path = ROOT / '.dart_tool/package_config.json'
    config_bytes = config_path.read_bytes()
    config = json.loads(config_bytes)
    packages = [entry for entry in config['packages'] if entry.get('name') == 'rgb_sdk_flutter']
    if len(packages) != 1 or not isinstance(packages[0].get('rootUri'), str):
        raise RuntimeError('Resolved SDK package is missing or ambiguous')
    uri = urlsplit(urljoin(config_path.resolve().as_uri(), packages[0]['rootUri']))
    if uri.scheme != 'file' or uri.netloc not in ('', 'localhost') or uri.query or uri.fragment:
        raise RuntimeError('Resolved SDK must be a local Git package checkout')
    sdk_root = Path(urllib.request.url2pathname(uri.path)).resolve()
    def git_value(*arguments):
        return subprocess.check_output(['git', *arguments], cwd=sdk_root,
                                       text=True, stderr=subprocess.PIPE).strip()
    if (Path(git_value('rev-parse', '--show-toplevel')).resolve() != sdk_root
            or git_value('rev-parse', 'HEAD') != requested
            or git_value('status', '--porcelain', '--untracked-files=normal')):
        raise RuntimeError('Resolved SDK checkout is not clean at the locked commit')
    return {'root': str(sdk_root), 'repository': repository, 'ref': requested,
            'packageConfigSha256': hashlib.sha256(config_bytes).hexdigest()}


def final_source_identity(root):
    """Retain the outcome report even if source files disappear during a run."""
    try:
        return source_identity(root)
    except (OSError, subprocess.SubprocessError) as error:
        return {'validationError': type(error).__name__}


def final_digest(path):
    try:
        return digest(path)
    except OSError:
        return None


def read_events(run_id):
    path = EVIDENCE / 'events.jsonl'
    result = []
    if path.exists():
        for line in path.read_text().splitlines():
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            if event.get('run_id') == run_id:
                result.append(event)
    return result


def write_ack(event_id, payload):
    if not re.fullmatch(r'[A-Za-z0-9_-]{1,120}', event_id):
        raise RuntimeError('Invalid fixture acknowledgement identity')
    path = EVIDENCE / 'commands' / (event_id + '.json')
    with path.open('x') as stream:
        json.dump({'ok': True, **payload}, stream)
        stream.flush()
        os.fsync(stream.fileno())
    sync_directory(path.parent)


def app_container(args):
    value = subprocess.check_output(
        ['xcrun', 'simctl', 'get_app_container', args.device, PACKAGE, 'data'],
        text=True, stderr=subprocess.PIPE,
    ).strip()
    container = Path(value).resolve()
    allowed = (Path.home() / 'Library/Developer/CoreSimulator/Devices' / args.device
               / 'data/Containers/Data/Application').resolve()
    if not container.is_dir() or not container.is_relative_to(allowed):
        raise RuntimeError('Aster simulator container identity could not be verified')
    return container


def preserve(event, args, output):
    if event.get('native_disposed') is not True:
        raise RuntimeError('Native ownership is not closed; snapshot acknowledgement refused')
    fixture = event['storage_root']
    storage_id = args.restore_from or args.run_id
    if args.device.startswith('emulator-'):
        if not re.fullmatch(
            r'/data/[A-Za-z0-9_./-]+/aster_full_wallet_qa/' + re.escape(storage_id), fixture
        ) or '..' in fixture.split('/'):
            raise RuntimeError('Unowned Android fixture refused')
        adb = os.environ.get('ADB_BIN', str(Path.home() / 'Library/Android/sdk/platform-tools/adb'))
        archive = output / 'private-device-state.tar'
        with archive.open('xb') as stream:
            copied = subprocess.run(
                [adb, '-s', args.device, 'exec-out', 'run-as', PACKAGE,
                 'tar', '-C', fixture, '-cf', '-', '.'],
                stdout=stream, stderr=subprocess.PIPE,
            )
        archive.chmod(0o600)
        if copied.returncode or archive.stat().st_size == 0:
            raise RuntimeError('Closed Android fixture copy failed')
        with archive.open('rb') as stream:
            os.fsync(stream.fileno())
        sync_directory(output)
        sync_directory(output.parent)
        return {'status': 'saved', 'nativeClosed': event['native_disposed'],
                'sha256': digest(archive), 'bytes': archive.stat().st_size,
                'credentialPolicy': 'original app Keystore and encrypted preferences retained; do not uninstall'}
    source = Path(fixture)
    allowed = app_container(args)
    if (not source.resolve().is_relative_to(allowed.resolve())
            or source.name != storage_id or source.parent.name != 'aster_full_wallet_qa'):
        raise RuntimeError('Unowned iOS fixture refused')
    target = output / 'private-device-state'
    shutil.copytree(source, target, symlinks=True)
    manifest_sha256 = sync_private_tree(target)
    sync_directory(output)
    sync_directory(output.parent)
    return {'status': 'saved', 'nativeClosed': event['native_disposed'],
            'filesManifestSha256': manifest_sha256,
            'credentialPolicy': 'same simulator Keychain account retained; snapshot is not portable recovery'}


def restore_fixture(event, args, source, expected_manifest=None):
    if args.device.startswith('emulator-'):
        raise RuntimeError('Android original Keystore must remain installed; refusing cross-install restore')
    target = Path(event['storage_root'])
    allowed = app_container(args)
    if (not target.resolve().is_relative_to(allowed.resolve()) or target.name != args.restore_from
            or target.parent.name != 'aster_full_wallet_qa' or target.exists()
            or event.get('storage_run_id') != args.restore_from):
        raise RuntimeError('Unowned or nonempty restore destination refused')
    # Copy actual closed files only; do not reconstruct a wallet from a seed.
    # Original same-simulator Keychain credentials stay in their own account.
    actual_manifest = tree_digest(source)
    if expected_manifest is not None and actual_manifest != expected_manifest:
        raise RuntimeError('Closed snapshot changed before restore copy')
    shutil.copytree(source, target, symlinks=True)
    if sync_private_tree(target) != actual_manifest:
        raise RuntimeError('Restored snapshot differs from verified closed bytes')
    sync_directory(target.parent)


def mint_reconciliation_source(args, config_sha, consumer_sha, contract_sha, asset_id,
                               sdk_dependency, app_identity, sdk_identity):
    """Admit only the known post-mint harness failure, never replay its mint."""
    source = EVIDENCE / args.restore_from
    report_path = source / 'result.json'
    if source.is_symlink() or report_path.is_symlink():
        raise RuntimeError('Linked reconciliation source refused')
    report = json.loads(report_path.read_text())
    if (report.get('schemaVersion') != 1 or report.get('status') != 'failed'
            or report.get('stage') != 'full' or report.get('runId') != args.restore_from
            or report.get('device') != args.device or type(report.get('exitCode')) is not int
            or report['exitCode'] != 1
            or report.get('runnerError') is not None
            or any(report.get(key) is not False for key in (
                'appSourceChangedDuringRun', 'sdkSourceChangedDuringRun',
                'configurationChangedDuringRun'))
            or report.get('appConfigSha256') != config_sha
            or report.get('appConfigSha256AtEnd') != config_sha
            or report.get('consumerConfigSha256') != consumer_sha
            or report.get('consumerConfigSha256AtEnd') != consumer_sha
            or report.get('publicContractSha256') != contract_sha
            or report.get('sdkDependencyBefore') != report.get('sdkDependencyAfter')
            or any(report.get('sdkDependencyBefore', {}).get(key) != sdk_dependency[key]
                   for key in ('ref', 'repository', 'root'))):
        raise RuntimeError('Reconciliation source identity or configuration differs')
    verify_closed_backup(source, args.device, report.get('privateFixtureBackup'))
    manifest_path = source / 'source-before.json'
    if manifest_path.is_symlink():
        raise RuntimeError('Linked original source manifest refused')
    manifest = json.loads(manifest_path.read_text())
    original_files = manifest.get('app', {}).get('files')
    if (not isinstance(original_files, dict) or manifest.get('sdk') != sdk_identity
            or manifest.get('sdkDependency') != report['sdkDependencyBefore']
            or manifest.get('appConfigSha256') != config_sha
            or manifest.get('consumerConfigSha256') != consumer_sha):
        raise RuntimeError('Reconciliation original source manifest or SDK differs')
    current_files = app_identity['files']
    changed_files = {key for key in set(original_files) | set(current_files)
                     if original_files.get(key) != current_files.get(key)}
    if not changed_files.issubset(RECONCILIATION_SOURCE_CHANGES):
        raise RuntimeError('Production app or build source changed since the original mint')
    events = report.get('events')
    role = 'app-android17' if args.device.startswith('emulator-') else 'app-ios27'
    if (not isinstance(events, list)
            or any(not isinstance(event, dict) or event.get('run_id') != args.restore_from
                   or event.get('role') != role for event in events)):
        raise RuntimeError('Reconciliation event ownership differs')
    def one(name):
        values = [event for event in events if event.get('event') == name]
        if len(values) != 1:
            raise RuntimeError('Reconciliation requires exactly one ' + name)
        return values[0]
    failure = one('test_failed')
    if (failure.get('code') != 'qa_private_field_rejected'
            or failure.get('diagnostics') != []
            or failure.get('sensitive_screen_active') is not False
            or any(event.get('event') == 'test_passed' for event in events)):
        raise RuntimeError('Only the known public-field harness failure can be reconciled')
    onboarding = one('onboarding_passed')
    reopened = one('same_store_bootstrap_passed')
    pubkey = onboarding.get('node_public_key')
    if (not isinstance(pubkey, str) or not re.fullmatch(r'0[23][a-f0-9]{64}', pubkey)
            or reopened.get('node_public_key') != pubkey):
        raise RuntimeError('Reconciliation original wallet identity differs')
    mint = one('bfa_mint_requested')
    mint_id = mint.get('id')
    if (type(mint.get('amount_units')) is not int or mint['amount_units'] != 5000000
            or not isinstance(mint.get('invoice'), str) or not mint['invoice']
            or not isinstance(mint_id, str)
            or not re.fullmatch(re.escape(args.restore_from + '-' + role + '-') + r'[0-9]+', mint_id)):
        raise RuntimeError('Reconciliation mint request differs')
    after_mint = events[events.index(mint) + 1:]
    if (events.index(failure) <= events.index(mint)
            or any(event.get('event') not in {
                'test_failed', 'test_cleanup', 'fixture_backup_requested', 'fixture_backup_verified'
            } for event in after_mint)
            or any(event.get('event') == 'bfa_burn_requested' for event in events)
            or sum(event.get('event') == 'fund_requested' for event in events) != 1
            or sum(event.get('event') == 'btc_confirm_requested' for event in events) != 1
            or one('test_cleanup').get('native_disposed') is not True):
        raise RuntimeError('Reconciliation refuses additional or uncertain wallet operations')
    acknowledgement_path = EVIDENCE / 'commands' / (mint_id + '.json')
    if acknowledgement_path.is_symlink():
        raise RuntimeError('Linked mint acknowledgement refused')
    acknowledgement = json.loads(acknowledgement_path.read_text())
    backend_mint = acknowledgement.get('mint')
    if (acknowledgement.get('ok') is not True or acknowledgement.get('id') != mint_id
            or acknowledgement.get('role') != role
            or acknowledgement.get('event') != 'bfa_mint_requested'
            or acknowledgement.get('localTestOnly') is not True
            or acknowledgement.get('amount_units') != '5000000'
            or acknowledgement.get('asset_id') != asset_id
            or type(acknowledgement.get('evm_chain_id')) is not int
            or acknowledgement['evm_chain_id'] != 42161
            or acknowledgement.get('receiverBalanceVerified') is not False
            or not isinstance(backend_mint, dict) or backend_mint.get('amount') != '5000000'
            or backend_mint.get('invoice') != mint['invoice']
            or backend_mint.get('phase') != 'backend_completed_receiver_unverified'):
        raise RuntimeError('Persisted mint acknowledgement differs; no mutation replay permitted')
    bitcoin = one('rgb_setup_bitcoin_balance')
    if (any(type(bitcoin.get(key)) is not int or not 0 <= bitcoin[key] <= 0x7fffffffffffffff
            for key in ('settled_sats', 'future_sats', 'spendable_sats', 'locked_sats'))
            or bitcoin['settled_sats'] > bitcoin['future_sats']
            or bitcoin['spendable_sats'] + bitcoin['locked_sats'] != bitcoin['future_sats']
            or bitcoin.get('setup_phase') not in ('pending', 'ready')
            or events.index(bitcoin) >= events.index(mint)):
        raise RuntimeError('Reconciliation Bitcoin checkpoint is malformed')
    expected = {
        'node_public_key': pubkey,
        'btc_future_sats': bitcoin['future_sats'],
        'btc_spendable_sats': bitcoin['spendable_sats'],
        'bfa_settled_units': 5000000, 'bfa_spendable_units': 5000000,
    }
    evidence = {
        'sourceRunId': args.restore_from, 'sourceReportSha256': digest(report_path),
        'mintAcknowledgementId': mint_id,
        'mintAcknowledgementSha256': digest(acknowledgement_path),
        'sourceManifestSha256': digest(manifest_path),
        'permittedSourceChanges': sorted(changed_files),
        'hostVerifiedReceiverBalance': False,
    }
    return report, expected, evidence


def transfer_reconciliation_source(args, config_sha, consumer_sha, contract_sha, asset_id,
                                   sdk_dependency, app_identity, sdk_identity):
    """Admit the one closed G transfer; sync its existing state, never resend.

    G's framework error ended the driver before its still-running test future.
    The original failed report remains immutable. Separate, durable late-event
    and preservation receipts bind the eventual timeout and native closure.
    """
    if args.restore_from != TRANSFER_RECONCILIATION_RUN or args.device.startswith('emulator-'):
        raise RuntimeError('Only the known same-iOS G transfer checkpoint can be reconciled')
    source = EVIDENCE / args.restore_from
    names = ('result.json', 'source-before.json', 'late-events.json',
             'preservation.json', 'late-preservation.json', 'flutter.log', 'invocation.json')
    if source.is_symlink() or any((source / name).is_symlink() for name in names):
        raise RuntimeError('Linked transfer reconciliation evidence refused')
    bound = {name: digest(source / name) for name in names}
    if bound['late-events.json'] != TRANSFER_RECONCILIATION_EVENTS_SHA256:
        raise RuntimeError('Known original G late journal hash differs')
    report = json.loads((source / 'result.json').read_text())
    if (report.get('schemaVersion') != 1 or report.get('status') != 'failed'
            or report.get('runId') != args.restore_from or report.get('stage') != 'full'
            or report.get('device') != args.device or type(report.get('exitCode')) is not int
            or report['exitCode'] != 1 or report.get('runnerError') is not None
            or report.get('privateFixtureBackup') != {'status': 'unavailable'}
            or report.get('flutterLogSha256') != bound['flutter.log']
            or any(report.get(key) is not False for key in (
                'appSourceChangedDuringRun', 'sdkSourceChangedDuringRun', 'configurationChangedDuringRun'))
            or report.get('appConfigSha256') != config_sha
            or report.get('appConfigSha256AtEnd') != config_sha
            or report.get('consumerConfigSha256') != consumer_sha
            or report.get('consumerConfigSha256AtEnd') != consumer_sha
            or report.get('publicContractSha256') != contract_sha
            or report.get('sdkDependencyBefore') != sdk_dependency
            or report.get('sdkDependencyAfter') != sdk_dependency):
        raise RuntimeError('Original G failed report, SDK or configuration differs')
    manifest = json.loads((source / 'source-before.json').read_text())
    original_files = manifest.get('app', {}).get('files')
    if (not isinstance(original_files, dict) or manifest.get('sdk') != sdk_identity
            or manifest.get('sdkDependency') != sdk_dependency
            or manifest.get('appConfigSha256') != config_sha
            or manifest.get('consumerConfigSha256') != consumer_sha):
        raise RuntimeError('Original G source manifest or native SDK differs')
    current_files = app_identity['files']
    changed = {name for name in set(original_files) | set(current_files)
               if original_files.get(name) != current_files.get(name)}
    if not changed.issubset(TRANSFER_RECONCILIATION_SOURCE_CHANGES):
        raise RuntimeError('Production source changed before G transfer reconciliation')
    invocation = json.loads((source / 'invocation.json').read_text())
    if invocation != {'schemaVersion': 1, 'runId': args.restore_from, 'device': args.device,
                      'package': PACKAGE, 'stage': 'full', 'storageRunId': args.restore_from}:
        raise RuntimeError('Original G invocation ownership differs')
    preservation = json.loads((source / 'preservation.json').read_text())
    backup = preservation.get('backup')
    if (preservation.get('schemaVersion') != 1 or preservation.get('runId') != args.restore_from
            or preservation.get('device') != args.device or preservation.get('package') != PACKAGE
            or preservation.get('storageRunId') != args.restore_from):
        raise RuntimeError('G late preservation owner differs')
    verify_closed_backup(source, args.device, backup)
    late = json.loads((source / 'late-preservation.json').read_text())
    if (late.get('schemaVersion') != 1 or late.get('sourceReportSha256') != bound['result.json']
            or late.get('sourceReportPreserved') is not True or late.get('nativeClosed') is not True
            or type(late.get('financialRequestsSent')) is not int or late['financialRequestsSent'] != 0
            or late.get('backup') != backup):
        raise RuntimeError('G supplemental closure does not bind the original failed report')
    events = json.loads((source / 'late-events.json').read_text())
    original_events = report.get('events')
    role = 'app-ios27'
    if (not isinstance(events, list) or not isinstance(original_events, list)
            or events[:len(original_events)] != original_events
            or events != read_events(args.restore_from)
            or any(not isinstance(event, dict) or event.get('run_id') != args.restore_from
                   or event.get('role') != role for event in events)):
        raise RuntimeError('G late journal differs from original prefix or live journal')
    def one(name):
        values = [event for event in events if event.get('event') == name]
        if len(values) != 1:
            raise RuntimeError('G transfer reconciliation requires exactly one ' + name)
        return values[0]
    failure = one('test_failed')
    sent = one('bfa_transfer_submitted')
    txid = sent.get('txid')
    if (failure.get('code') != 'qa_import_wallet_state_timeout' or failure.get('diagnostics') != []
            or failure.get('sensitive_screen_active') is not False
            or not isinstance(txid, str) or not re.fullmatch(r'[a-f0-9]{64}', txid)
            or type(sent.get('amount_units')) is not int or sent['amount_units'] != 1000000
            or events.index(sent) < len(original_events)
            or events[events.index(sent) + 1:] != [failure, one('test_cleanup'),
                                                   one('fixture_backup_requested'), one('fixture_backup_verified')]
            or one('test_cleanup').get('native_disposed') is not True
            or one('fixture_backup_requested').get('native_disposed') is not True
            or one('fixture_backup_requested').get('stage') != 'full'
            or late.get('requestId') != one('fixture_backup_requested').get('id')):
        raise RuntimeError('G late transfer has additional operations or an unexpected failure')
    if any(event.get('event') in {'test_passed', 'bfa_burn_requested', 'identity_requested'} for event in events):
        raise RuntimeError('G checkpoint contains an unexpected financial operation')
    original_key = one('onboarding_passed').get('node_public_key')
    imported_key = one('import_passed').get('node_public_key')
    if (any(not isinstance(key, str) or not re.fullmatch(r'0[23][a-f0-9]{64}', key)
            for key in (original_key, imported_key)) or original_key == imported_key
            or one('same_store_bootstrap_passed').get('node_public_key') != original_key
            or one('bfa_receive_passed').get('node_public_key') != original_key
            or any(type(one('bfa_receive_passed').get(key)) is not int
                   or one('bfa_receive_passed')[key] != 5000000
                   for key in ('bfa_settled_units', 'bfa_future_units', 'bfa_spendable_units'))
            or any(type(one('import_passed').get(key)) is not int or one('import_passed')[key] != 0
                   for key in ('btc_settled_sats', 'btc_spendable_sats',
                               'bfa_settled_units', 'bfa_future_units', 'bfa_spendable_units'))):
        raise RuntimeError('G original or imported wallet identity/balance differs')
    accepted = [event for event in events if event.get('event') == 'send_ui_accepted']
    confirmed = [event for event in events if event.get('event') == 'send_ui_confirm_requested']
    if (len(accepted) != 2 or len(confirmed) != 2
            or [(event.get('target'), event.get('amount_units')) for event in accepted]
            != [('bitcoin-onchain', 20000), ('usdt-onchain', 1000000)]
            or [(event.get('target'), event.get('amount_units')) for event in confirmed]
            != [('bitcoin-onchain', 20000), ('usdt-onchain', 1000000)]
            or any(type(event.get('amount_units')) is not int for event in accepted + confirmed)
            or accepted[1].get('txid') != txid):
        raise RuntimeError('G accepted send checkpoint differs; no send replay permitted')
    prepared = one('imported_receive_prepared')
    if (type(prepared.get('amount_units')) is not int or prepared['amount_units'] != 1000000
            or prepared.get('invoice_amount_bound') is not False
            or not isinstance(prepared.get('invoice'), str) or not prepared['invoice']):
        raise RuntimeError('G existing receiver invoice checkpoint differs')
    funds = [event for event in events if event.get('event') == 'fund_requested']
    mint = one('bfa_mint_requested')
    btc = one('btc_confirm_requested')
    if (len(funds) != 2 or len({event.get('id') for event in funds}) != 2
            or any(not isinstance(event.get('address'), str) or not event['address'] for event in funds)
            or len({event.get('address') for event in funds}) != 2
            or any(type(event.get('amount_sats')) is not int
                             or event['amount_sats'] != 2000000 for event in funds)
            or type(mint.get('amount_units')) is not int or mint['amount_units'] != 5000000
            or type(btc.get('amount_sats')) is not int or btc['amount_sats'] != 20000
            or btc.get('txid') != accepted[0].get('txid')):
        raise RuntimeError('G funding and initial mint counts differ')
    fund_txids = []
    for request in [*funds, mint, btc, one('fixture_backup_requested')]:
        request_id = request.get('id')
        if (not isinstance(request_id, str)
                or not re.fullmatch(re.escape(args.restore_from + '-' + role + '-') + r'[0-9]+', request_id)):
            raise RuntimeError('G coordinator request ownership differs')
        path = EVIDENCE / 'commands' / (request_id + '.json')
        if path.is_symlink():
            raise RuntimeError('Linked G coordinator acknowledgement refused')
        acknowledgement = json.loads(path.read_text())
        bound['../commands/' + path.name] = digest(path)
        if acknowledgement.get('ok') is not True:
            raise RuntimeError('G coordinator acknowledgement is not successful')
        if request['event'] == 'fixture_backup_requested':
            if acknowledgement.get('backup_verified') is not True:
                raise RuntimeError('G backup was not acknowledged')
            continue
        if any(acknowledgement.get(key) != request.get(key) for key in ('id', 'role', 'event')):
            raise RuntimeError('G financial acknowledgement ownership differs')
        if request['event'] == 'fund_requested':
            if (type(acknowledgement.get('amount_sats')) is not int
                    or acknowledgement['amount_sats'] != 2000000
                    or acknowledgement.get('address') != request.get('address')
                    or acknowledgement.get('confirmed') is not True
                    or not isinstance(acknowledgement.get('txid'), str)
                    or not re.fullmatch(r'[a-f0-9]{64}', acknowledgement['txid'])):
                raise RuntimeError('G prior funding acknowledgement differs')
            fund_txids.append(acknowledgement['txid'])
        elif request['event'] == 'btc_confirm_requested':
            if (acknowledgement.get('txid') != btc['txid']
                    or type(acknowledgement.get('amount_sats')) is not int
                    or acknowledgement['amount_sats'] != 20000
                    or acknowledgement.get('recipient') != btc.get('recipient')
                    or acknowledgement.get('confirmed') is not True):
                raise RuntimeError('G prior BTC confirmation acknowledgement differs')
        else:
            backend = acknowledgement.get('mint')
            if (acknowledgement.get('amount_units') != '5000000' or acknowledgement.get('asset_id') != asset_id
                    or type(acknowledgement.get('evm_chain_id')) is not int or acknowledgement['evm_chain_id'] != 42161
                    or acknowledgement.get('localTestOnly') is not True
                    or acknowledgement.get('receiverBalanceVerified') is not False
                    or not isinstance(backend, dict) or backend.get('amount') != '5000000'
                    or backend.get('invoice') != mint.get('invoice')
                    or backend.get('phase') != 'backend_completed_receiver_unverified'):
                raise RuntimeError('G prior mint acknowledgement differs')
    if len(set(fund_txids)) != 2:
        raise RuntimeError('G requires two distinct prior funding transactions')
    # Registry identity is public metadata in the already hash-verified closed
    # snapshot. Native pubkeys are mapped to these IDs by read-only activation.
    slots = []
    for path in sorted((source / 'private-device-state/metadata').glob('wallet_registry.*.json')):
        outer = json.loads(path.read_text())
        generation, document = outer.get('generation'), outer.get('document')
        if (outer.get('schema') != 1 or type(generation) is not int or generation < 0
                or not isinstance(document, str)
                or hashlib.sha256(('1\n' + str(generation) + '\n' + document).encode()).hexdigest()
                != outer.get('checksum')):
            raise RuntimeError('G retained registry checksum differs')
        slots.append((generation, document))
    slots.sort(key=lambda slot: slot[0])
    if not slots or (len(slots) > 1 and slots[-1][0] == slots[-2][0] and slots[-1][1] != slots[-2][1]):
        raise RuntimeError('G retained registry is unavailable or ambiguous')
    registry = json.loads(max(slots, key=lambda slot: slot[0])[1])
    profiles = registry.get('profiles')
    if not isinstance(profiles, list) or len(profiles) != 2:
        raise RuntimeError('G must retain exactly two existing profiles')
    ids = sorted(profile.get('id', '') for profile in profiles)
    if (len(set(ids)) != 2 or any(not isinstance(value, str) or not re.fullmatch(r'[a-f0-9]{32}', value) for value in ids)
            or any(profile.get('state') != 'ready' or profile.get('environment') != 'regtest' for profile in profiles)
            or registry.get('activeWalletId') not in ids):
        raise RuntimeError('G retained profile ownership differs')
    expected = {
        'profile_ids': ids, 'active_wallet_id': registry['activeWalletId'],
        'original_public_key': original_key, 'imported_public_key': imported_key,
        'txid': txid, 'invoice': prepared['invoice'],
        'amount_units': 1000000, 'original_units': 4000000, 'imported_units': 1000000,
    }
    evidence = {'sourceRunId': args.restore_from, 'boundFiles': bound,
                'permittedSourceChanges': sorted(changed), 'originalResultRemainsFailed': True,
                'filesManifestSha256': backup['filesManifestSha256']}
    return {**report, 'privateFixtureBackup': backup}, expected, evidence


def transfer_reconciliation_changed(evidence):
    source = EVIDENCE / evidence['sourceRunId']
    try:
        changed = (any((source / name).is_symlink() or final_digest(source / name) != expected
                    for name, expected in evidence['boundFiles'].items())
                or tree_digest(source / 'private-device-state') != evidence['filesManifestSha256']
                or json.loads((source / 'late-events.json').read_text()) != read_events(evidence['sourceRunId']))
        checkpoint = evidence.get('checkpoint')
        if checkpoint is not None:
            latest = EVIDENCE / checkpoint['runId']
            changed = changed or (
                any((latest / name).is_symlink() or final_digest(latest / name) != expected
                    for name, expected in checkpoint['boundFiles'].items())
                or tree_digest(latest / 'private-device-state') != checkpoint['filesManifestSha256']
                or json.loads((latest / 'result.json').read_text())['events'] != read_events(checkpoint['runId']))
        return changed
    except (OSError, ValueError, TypeError, RuntimeError):
        return True


def transfer_reconciliation_checkpoint(args, expected, evidence, sdk_dependency,
                                       app_identity, sdk_identity, config_sha, consumer_sha):
    """Use A's newest closed bytes, retaining G's original transaction intent."""
    if args.checkpoint_from != TRANSFER_RECONCILIATION_CHECKPOINT:
        raise RuntimeError('Only the known closed A transfer checkpoint may resume G')
    output = EVIDENCE / args.checkpoint_from
    names = ('result.json', 'source-before.json', 'invocation.json', 'preservation.json', 'flutter.log')
    if output.is_symlink() or any((output / name).is_symlink() for name in names):
        raise RuntimeError('Linked resumed transfer checkpoint refused')
    bound = {name: digest(output / name) for name in names}
    if bound['result.json'] != TRANSFER_RECONCILIATION_CHECKPOINT_REPORT:
        raise RuntimeError('Known original closed A checkpoint report hash differs')
    report = json.loads((output / 'result.json').read_text())
    if (report.get('schemaVersion') != 1 or report.get('runId') != args.checkpoint_from
            or report.get('device') != args.device or report.get('status') != 'failed'
            or report.get('stage') != 'reconcile-transfer' or report.get('restoredFromRun') != args.restore_from
            or type(report.get('exitCode')) is not int or report['exitCode'] != 1
            or report.get('runnerError') is not None or report.get('flutterLogSha256') != bound['flutter.log']
            or report.get('appConfigSha256') != config_sha or report.get('appConfigSha256AtEnd') != config_sha
            or report.get('consumerConfigSha256') != consumer_sha or report.get('consumerConfigSha256AtEnd') != consumer_sha
            or report.get('sdkDependencyBefore') != sdk_dependency or report.get('sdkDependencyAfter') != sdk_dependency
            or any(report.get(key) is not False for key in (
                'appSourceChangedDuringRun', 'sdkSourceChangedDuringRun', 'configurationChangedDuringRun',
                'restoreEvidenceChangedDuringRun', 'reconciliationEvidenceChangedDuringRun'))
            or report.get('reconciliationSource', {}).get('boundFiles') != evidence['boundFiles']
            or report.get('reconciliationSource', {}).get('filesManifestSha256') != evidence['filesManifestSha256']
            or report.get('reconciliationSource', {}).get('sourceRunId') != args.restore_from):
        raise RuntimeError('Closed A transfer checkpoint provenance differs')
    manifest = json.loads((output / 'source-before.json').read_text())
    files = manifest.get('app', {}).get('files')
    if (not isinstance(files, dict) or manifest.get('sdk') != sdk_identity
            or manifest.get('sdkDependency') != sdk_dependency or manifest.get('appConfigSha256') != config_sha
            or manifest.get('consumerConfigSha256') != consumer_sha
            or not {name for name in set(files) | set(app_identity['files'])
                    if files.get(name) != app_identity['files'].get(name)}.issubset(TRANSFER_RECONCILIATION_SOURCE_CHANGES)):
        raise RuntimeError('Production source changed since closed A transfer checkpoint')
    invocation = json.loads((output / 'invocation.json').read_text())
    if invocation != {'schemaVersion': 1, 'runId': args.checkpoint_from, 'device': args.device,
                      'package': PACKAGE, 'stage': 'reconcile-transfer', 'storageRunId': args.restore_from}:
        raise RuntimeError('Closed A checkpoint invocation owner differs')
    events = report.get('events')
    if (not isinstance(events, list) or events != read_events(args.checkpoint_from)
            or [event.get('event') for event in events] != [
                'test_started', 'public_network_preflight', 'fixture_transfer_validation_requested',
                'test_failed', 'test_cleanup', 'fixture_backup_requested', 'fixture_backup_verified']
            or any(event.get('run_id') != args.checkpoint_from or event.get('role') != 'app-ios27' for event in events)
            or events[3].get('code') != 'qa_transfer_original_native_checkpoint_changed'
            or events[3].get('diagnostics') != [] or events[3].get('sensitive_screen_active') is not False
            or events[4].get('native_disposed') is not True or events[5].get('native_disposed') is not True
            or events[5].get('stage') != 'reconcile-transfer'):
        raise RuntimeError('Closed A checkpoint has an unexpected failure or financial operation')
    for event, key, value in [(events[2], 'expected_transfer', expected),
                              (events[5], 'backup_verified', True)]:
        request_id = event.get('id')
        if (not isinstance(request_id, str)
                or not re.fullmatch(re.escape(args.checkpoint_from + '-app-ios27-') + r'[0-9]+', request_id)):
            raise RuntimeError('Closed A checkpoint acknowledgement owner differs')
        path = EVIDENCE / 'commands' / (request_id + '.json')
        if path.is_symlink():
            raise RuntimeError('Linked closed A checkpoint acknowledgement refused')
        ack = json.loads(path.read_text())
        if ack.get('ok') is not True or ack.get(key) != value:
            raise RuntimeError('Closed A checkpoint acknowledgement differs')
        bound['../commands/' + path.name] = digest(path)
    backup = report.get('privateFixtureBackup')
    if (not isinstance(backup, dict)
            or backup.get('filesManifestSha256') != TRANSFER_RECONCILIATION_CHECKPOINT_MANIFEST):
        raise RuntimeError('Known original closed A checkpoint manifest differs')
    verify_closed_backup(output, args.device, backup)
    preservation = json.loads((output / 'preservation.json').read_text())
    if preservation != {'schemaVersion': 1, 'runId': args.checkpoint_from, 'device': args.device,
                         'package': PACKAGE, 'storageRunId': args.restore_from, 'backup': backup}:
        raise RuntimeError('Closed A checkpoint preservation receipt differs')
    # Preserve the exact two profile IDs and active selection in the latest
    # closed registry. Its loader will independently validate both slot hashes.
    slots = [json.loads(path.read_text()) for path in (output / 'private-device-state/metadata').glob('wallet_registry.*.json')]
    if not slots or any(type(slot.get('generation')) is not int or not isinstance(slot.get('document'), str) for slot in slots):
        raise RuntimeError('Closed A checkpoint registry unavailable')
    registry = json.loads(max(slots, key=lambda slot: slot['generation'])['document'])
    profiles = registry.get('profiles')
    if (not isinstance(profiles, list) or len(profiles) != 2
            or sorted(profile.get('id', '') for profile in profiles) != expected['profile_ids']
            or any(profile.get('state') != 'ready' or profile.get('environment') != 'regtest' for profile in profiles)
            or registry.get('activeWalletId') != expected['active_wallet_id']):
        raise RuntimeError('Closed A checkpoint retained profiles differ')
    evidence['checkpoint'] = {'runId': args.checkpoint_from, 'boundFiles': bound,
                              'filesManifestSha256': backup['filesManifestSha256']}
    return report, output / 'private-device-state'


def restore_pair_checkpoint(passed):
    """Require a complete, canonical two-profile checkpoint from the full run."""
    pair = passed.get('wallet_pair')
    if (not isinstance(pair, dict) or set(pair) != {'active_wallet_id', 'profiles'}
            or not isinstance(pair['active_wallet_id'], str)
            or not isinstance(pair['profiles'], list) or len(pair['profiles']) != 2):
        raise RuntimeError('Full restore requires both retained profile checkpoints')
    amount_keys = ('btc_settled_sats', 'btc_future_sats', 'btc_spendable_sats',
                   'bfa_settled_units', 'bfa_future_units', 'bfa_spendable_units')
    profile_keys = {'wallet_id', 'node_public_key', *amount_keys}
    identities = []
    pubkeys = []
    for profile in pair['profiles']:
        if (not isinstance(profile, dict) or set(profile) != profile_keys
                or not isinstance(profile['wallet_id'], str)
                or not re.fullmatch(r'[a-f0-9]{32}', profile['wallet_id'])
                or not isinstance(profile['node_public_key'], str)
                or not re.fullmatch(r'0[23][a-f0-9]{64}', profile['node_public_key'])
                or any(type(profile[key]) is not int or not 0 <= profile[key] <= 0x7fffffffffffffff
                       for key in amount_keys)
                or profile['btc_settled_sats'] > profile['btc_future_sats']
                or profile['btc_spendable_sats'] > profile['btc_future_sats']
                or profile['bfa_spendable_units'] > profile['bfa_settled_units']):
            raise RuntimeError('Retained profile checkpoint is malformed')
        identities.append(profile['wallet_id'])
        pubkeys.append(profile['node_public_key'])
    if (len(set(identities)) != 2 or len(set(pubkeys)) != 2
            or identities != sorted(identities) or pair['active_wallet_id'] not in identities):
        raise RuntimeError('Retained pair identities or active selection differ')
    active = next(profile for profile in pair['profiles'] if profile['wallet_id'] == pair['active_wallet_id'])
    if (not isinstance(passed.get('node_public_key'), str)
            or any(type(passed.get(key)) is not int for key in amount_keys)
            or any(passed.get(key) != active[key] for key in ('node_public_key', *amount_keys))):
        raise RuntimeError('Final active snapshot differs from retained pair checkpoint')
    return pair


def restore_evidence_changed(evidence, device):
    """Bind the original closed wallet bytes through the whole cold restore."""
    if evidence is None:
        return False
    output = EVIDENCE / evidence['sourceRunId']
    try:
        if (output.is_symlink() or any((output / name).is_symlink() for name in (
                'result.json', 'source-before.json'))
                or digest(output / 'result.json') != evidence['sourceReportSha256']
                or digest(output / 'source-before.json') != evidence['sourceManifestSha256']):
            return True
        verify_closed_backup(output, device, evidence['sourceBackup'])
        return False
    except (OSError, ValueError, TypeError, KeyError, RuntimeError):
        return True


def parse_android_framework_health(boot, package, activity):
    """Require the actual service-check responses; exit zero is insufficient."""
    if (boot.strip() != '1' or package.strip() != 'Service package: found'
            or activity.strip() != 'Service activity: found'):
        raise RuntimeError('Owned Android framework is not ready; no app launch was attempted')
    return {'bootCompleted': True, 'packageServiceFound': True, 'activityServiceFound': True}


def android_framework_preflight(device):
    if not device.startswith('emulator-'):
        return None
    if not re.fullmatch(r'emulator-[0-9]+', device):
        raise RuntimeError('Invalid owned Android device identity')
    adb = os.environ.get('ADB_BIN', str(Path.home() / 'Library/Android/sdk/platform-tools/adb'))
    outputs = []
    for command in (['getprop', 'sys.boot_completed'], ['service', 'check', 'package'],
                    ['service', 'check', 'activity']):
        completed = subprocess.run([adb, '-s', device, 'shell', *command],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   text=True, timeout=10, check=False)
        if completed.returncode != 0:
            raise RuntimeError('Owned Android framework preflight command failed')
        outputs.append(completed.stdout)
    return {'device': device, **parse_android_framework_health(*outputs)}


def run_qualification(args, parser):
    checkpoint_from = getattr(args, 'checkpoint_from', None)
    if checkpoint_from and (args.stage != 'reconcile-transfer'
                            or not re.fullmatch(RUN_ID_PATTERN, checkpoint_from)):
        parser.error('checkpoint-from is permitted only for the known transfer continuation')
    admit_pretest = getattr(args, 'admit_pretest_failure', None)
    if admit_pretest and (args.stage not in ('full', 'restore') or args.device != 'emulator-5582'):
        parser.error('pretest admission is limited to the known Android launch before full/restore')
    prior_admissions = assert_prior_device_preserved(args.device, admit_pretest)
    if read_events(args.run_id):
        raise RuntimeError('Run already has events; inspect its journal, never replay it')
    restore_report = None
    restore_source = None
    expected_snapshot = None
    expected_pair = None
    expected_transfer = None
    reconciliation = None
    restore_evidence = None
    if args.stage in ('reconcile-mint', 'reconcile-transfer') and (
            not args.restore_from or not re.fullmatch(RUN_ID_PATTERN, args.restore_from)):
        parser.error('reconciliation requires the original known failed full run ID')
    if args.stage == 'restore':
        if not args.restore_from or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]{2,63}', args.restore_from):
            parser.error('restore requires the original successful full run ID')
        restore_output = EVIDENCE / args.restore_from
        report_path = restore_output / 'result.json'
        if restore_output.is_symlink() or report_path.is_symlink():
            raise RuntimeError('Linked restore source refused')
        restore_report = json.loads(report_path.read_text())
        if (restore_report.get('schemaVersion') != 1 or restore_report.get('runId') != args.restore_from
                or restore_report.get('status') != 'passed' or restore_report.get('stage') != 'full'
                or type(restore_report.get('exitCode')) is not int or restore_report['exitCode'] != 0
                or restore_report.get('runnerError') is not None
                or restore_report.get('device') != args.device
                or restore_report['privateFixtureBackup'].get('nativeClosed') is not True):
            raise RuntimeError('Restore source was not successfully closed and qualified on this device')
        passed_events = [e for e in restore_report['events'] if e.get('event') == 'test_passed']
        if len(passed_events) != 1 or passed_events[0].get('stage') != 'full':
            raise RuntimeError('Restore requires one successful full checkpoint')
        expected_pair = restore_pair_checkpoint(passed_events[0])
        expected_snapshot = {key: passed_events[0][key] for key in (
            'node_public_key', 'btc_settled_sats', 'btc_spendable_sats',
            'bfa_settled_units', 'bfa_spendable_units')}
        restore_source = restore_output / 'private-device-state'
        if not args.device.startswith('emulator-') and (
                not restore_source.is_dir()
                or tree_digest(restore_source) != restore_report['privateFixtureBackup'].get('filesManifestSha256')):
            raise RuntimeError('Closed iOS snapshot content hash differs; refusing restore')
    elif args.restore_from and args.stage not in ('reconcile-mint', 'reconcile-transfer'):
        parser.error('restore-from is permitted only for a read-only checkpoint stage')
    framework_preflight = android_framework_preflight(args.device)
    output = EVIDENCE / args.run_id
    output.mkdir(mode=0o700, parents=True, exist_ok=False)
    sync_directory(output.parent)
    config = ROOT / 'config' / ('shared-stack.android.local.json' if args.device.startswith('emulator-')
                              else 'shared-stack.ios.local.json')
    consumer_path = SHARED / 'artifacts/consumer-config.json'
    consumer_bytes = consumer_path.read_bytes()
    consumer = json.loads(consumer_bytes)
    asset = consumer['asset']
    if (consumer['environment'] != 'LOCAL TEST ONLY' or consumer['network'] != 'regtest'
            or consumer['evm_chain_id'] != 42161 or digest(Path(asset['public_contract'])) != asset['sha256']):
        raise RuntimeError('Shared consumer identity differs; review without changing infrastructure')
    with urllib.request.urlopen('http://127.0.0.1:29671/health', timeout=10) as response:
        if json.load(response) != {'ready': True, 'mutations': False}:
            raise RuntimeError('Existing evidence relay not ready')
    app_before = source_identity(ROOT)
    sdk_dependency_before = resolved_sdk_dependency()
    sdk_root = Path(sdk_dependency_before['root'])
    sdk_before = source_identity(sdk_root)
    config_before = digest(config)
    consumer_before = hashlib.sha256(consumer_bytes).hexdigest()
    if args.stage == 'restore':
        original_output = EVIDENCE / args.restore_from
        original_manifest_path = original_output / 'source-before.json'
        if original_output.is_symlink() or original_manifest_path.is_symlink():
            raise RuntimeError('Linked restore source refused')
        original_manifest = json.loads(original_manifest_path.read_text())
        if (restore_report.get('appConfigSha256') != config_before
                or restore_report.get('appConfigSha256AtEnd') != config_before
                or restore_report.get('consumerConfigSha256') != consumer_before
                or restore_report.get('consumerConfigSha256AtEnd') != consumer_before
                or restore_report.get('publicContractSha256') != asset['sha256']
                or any(restore_report.get(key) is not False for key in (
                    'appSourceChangedDuringRun', 'sdkSourceChangedDuringRun', 'configurationChangedDuringRun'))
                or original_manifest.get('app') != app_before or original_manifest.get('sdk') != sdk_before
                or original_manifest.get('sdkDependency') != sdk_dependency_before
                or original_manifest.get('appConfigSha256') != config_before
                or original_manifest.get('consumerConfigSha256') != consumer_before
                or restore_report.get('sdkDependencyBefore') != sdk_dependency_before
                or restore_report.get('sdkDependencyAfter') != sdk_dependency_before):
            raise RuntimeError('Restore original source, SDK or configuration differs')
        verify_closed_backup(original_output, args.device, restore_report.get('privateFixtureBackup'))
        restore_evidence = {
            'sourceRunId': args.restore_from,
            'sourceReportSha256': digest(original_output / 'result.json'),
            'sourceManifestSha256': digest(original_manifest_path),
            'sourceBackup': dict(restore_report['privateFixtureBackup']),
        }
    if args.stage == 'reconcile-mint':
        restore_report, expected_snapshot, reconciliation = mint_reconciliation_source(
            args, config_before, consumer_before, asset['sha256'], asset['id'],
            sdk_dependency_before, app_before, sdk_before)
        restore_source = EVIDENCE / args.restore_from / 'private-device-state'
    elif args.stage == 'reconcile-transfer':
        restore_report, expected_transfer, reconciliation = transfer_reconciliation_source(
            args, config_before, consumer_before, asset['sha256'], asset['id'],
            sdk_dependency_before, app_before, sdk_before)
        restore_source = EVIDENCE / args.restore_from / 'private-device-state'
        if checkpoint_from:
            restore_report, restore_source = transfer_reconciliation_checkpoint(
                args, expected_transfer, reconciliation, sdk_dependency_before,
                app_before, sdk_before, config_before, consumer_before)
        elif (EVIDENCE / TRANSFER_RECONCILIATION_CHECKPOINT / 'invocation.json').exists():
            raise RuntimeError('G has a newer native checkpoint; select checkpoint-from instead of rolling back')
    write_durable_json(output / 'source-before.json', {
        'app': app_before, 'sdk': sdk_before, 'sdkDependency': sdk_dependency_before,
        'appConfigSha256': config_before, 'consumerConfigSha256': consumer_before,
    })
    launch_flags = ['--no-start-paused', '--keep-app-running']
    command = [os.environ.get('FLUTTER_BIN', 'flutter'), 'drive', '--no-pub',
               '--driver=test_driver/integration_test.dart',
               '--target=integration_test/full_wallet_flow_test.dart',
               *launch_flags, '-d', args.device,
               '--dart-define-from-file=' + str(config),
               '--dart-define=ASTER_QA_RUN_ID=' + args.run_id,
               '--dart-define=ASTER_QA_STAGE=' + args.stage,
               '--dart-define=ASTER_QA_CONTROL_URL=http://127.0.0.1:29671']
    if args.restore_from:
        command.append('--dart-define=ASTER_QA_STORAGE_RUN_ID=' + args.restore_from)
    started = time.monotonic()
    backup = {'status': 'unavailable'}
    handled = set()
    runner_error = None
    with (output / 'flutter.log').open('x') as log:
        # An interrupted host runner must remain visible to the next launch.
        # All source/config/relay checks above complete before this marker.
        write_durable_json(output / 'invocation.json', {
            'schemaVersion': 1, 'runId': args.run_id, 'device': args.device,
            'package': PACKAGE, 'stage': args.stage,
            'storageRunId': args.restore_from or args.run_id,
        })
        process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
        def service_events():
            nonlocal backup
            events = read_events(args.run_id)
            for event in events:
                action = event.get('event')
                if action not in ('fixture_backup_requested', 'fixture_restore_requested',
                                  'fixture_restore_validation_requested',
                                  'fixture_reconcile_validation_requested',
                                  'fixture_transfer_validation_requested') or event['id'] in handled:
                    continue
                if action == 'fixture_backup_requested':
                    backup = preserve_and_ack(event, args, output)
                elif action == 'fixture_restore_requested':
                    if args.stage not in ('restore', 'reconcile-mint', 'reconcile-transfer'):
                        raise RuntimeError('Restore request outside read-only mode refused')
                    restore_fixture(event, args, restore_source,
                                    restore_report['privateFixtureBackup']['filesManifestSha256'])
                    write_ack(event['id'], {'restore_verified': True})
                else:
                    required_stage = {
                        'fixture_reconcile_validation_requested': 'reconcile-mint',
                        'fixture_transfer_validation_requested': 'reconcile-transfer',
                        'fixture_restore_validation_requested': 'restore',
                    }[action]
                    if args.stage != required_stage or event.get('storage_run_id') != args.restore_from:
                        raise RuntimeError('Restore verification owner mismatch')
                    payload = {'expected_snapshot': expected_snapshot}
                    if args.stage == 'restore':
                        payload['expected_pair'] = expected_pair
                    elif args.stage == 'reconcile-transfer':
                        payload = {'expected_transfer': expected_transfer}
                    write_ack(event['id'], payload)
                handled.add(event['id'])
            return (backup.get('status') == 'saved' and backup.get('nativeClosed') is True
                    and any(event.get('event') == 'test_cleanup'
                            and event.get('native_disposed') is True for event in events))
        try:
            code = coordinate_driver_exit(process, service_events)
        except Exception as error:
            # Preserve the app and any uncertain operation. Never kill a native
            # wallet just because private backup coordination failed.
            runner_error = type(error).__name__
            print('Runner coordination failed; app and financial journals preserved.', flush=True)
            code = process.wait()
    events = read_events(args.run_id)
    passed = any(e.get('event') == 'test_passed' for e in events)
    disposed = any(e.get('event') == 'test_cleanup' and e.get('native_disposed') is True for e in events)
    app_after = final_source_identity(ROOT)
    sdk_after = final_source_identity(sdk_root)
    try:
        sdk_dependency_after = resolved_sdk_dependency()
    except (OSError, ValueError, KeyError, TypeError, AttributeError,
            subprocess.SubprocessError, RuntimeError) as error:
        sdk_dependency_after = {'validationError': type(error).__name__}
    config_after = final_digest(config)
    consumer_after = final_digest(consumer_path)
    sdk_changed = sdk_before != sdk_after or sdk_dependency_before != sdk_dependency_after
    config_changed = config_before != config_after or consumer_before != consumer_after
    reconciliation_changed = reconciliation is not None and (transfer_reconciliation_changed(reconciliation)
        if args.stage == 'reconcile-transfer' else (
        final_digest(EVIDENCE / args.restore_from / 'result.json') != reconciliation['sourceReportSha256']
        or final_digest(EVIDENCE / args.restore_from / 'source-before.json')
        != reconciliation['sourceManifestSha256']
        or final_digest(EVIDENCE / 'commands' / (reconciliation['mintAcknowledgementId'] + '.json'))
        != reconciliation['mintAcknowledgementSha256']))
    restore_changed = restore_evidence_changed(restore_evidence, args.device)
    prior_admission_changed = any(known_pretest_admission_changed(item) for item in prior_admissions)
    source_changed = (app_before != app_after or sdk_changed or config_changed
                      or reconciliation_changed or restore_changed or prior_admission_changed)
    qualified = qualification_passed(code, passed, disposed, backup, runner_error, source_changed)
    result = {
        'schemaVersion': 1, 'suite': 'aster-shared-wallet', 'runId': args.run_id,
        'device': args.device, 'stage': args.stage,
        'restoredFromRun': args.restore_from,
        'checkpointFromRun': checkpoint_from,
        'priorLaunchAdmissions': prior_admissions,
        'priorLaunchEvidenceChangedDuringRun': prior_admission_changed,
        'restoreSource': restore_evidence,
        'restoreEvidenceChangedDuringRun': restore_changed,
        'reconciliationSource': reconciliation,
        'reconciliationEvidenceChangedDuringRun': reconciliation_changed,
        'status': 'passed' if qualified else 'failed',
        'exitCode': code, 'runnerError': runner_error,
        'launchFlags': launch_flags,
        'androidFrameworkPreflight': framework_preflight,
        'elapsedSeconds': round(time.monotonic() - started, 3),
        'consumerConfigSha256': consumer_before, 'appConfigSha256': config_before,
        'consumerConfigSha256AtEnd': consumer_after, 'appConfigSha256AtEnd': config_after,
        'configurationChangedDuringRun': config_changed,
        'sdkDependencyBefore': sdk_dependency_before, 'sdkDependencyAfter': sdk_dependency_after,
        'publicContractSha256': asset['sha256'],
        'appSourceChangedDuringRun': app_before != app_after,
        'sdkSourceChangedDuringRun': sdk_changed,
        'privateFixtureBackup': backup,
        'events': events,
        'flutterLogSha256': digest(output / 'flutter.log'),
        'infrastructureStarted': False, 'containersCreated': False, 'stateReset': False,
        'productionReady': False,
    }
    write_durable_json(output / 'source-after.json', {
        'app': app_after, 'sdk': sdk_after, 'sdkDependency': sdk_dependency_after,
        'appConfigSha256': config_after, 'consumerConfigSha256': consumer_after,
    })
    write_durable_json(output / 'result.json', result)
    print('Aster qualification ' + result['status'] + ': ' + str(output / 'result.json'), flush=True)
    return 0 if result['status'] == 'passed' else 1


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    parser.add_argument('--run-id', required=True)
    parser.add_argument('--stage', choices=('lifecycle', 'full', 'restore', 'reconcile-mint', 'reconcile-transfer'), default='full')
    parser.add_argument('--restore-from', help='retained same-device full run admitted by the checkpoint stage')
    parser.add_argument('--admit-pretest-failure', action='append',
                        help='repeat for each exact pinned failed pretest launch to admit')
    parser.add_argument('--checkpoint-from', help='latest closed A bytes for the known G transfer continuation')
    args = parser.parse_args()
    if not re.fullmatch(RUN_ID_PATTERN, args.run_id):
        parser.error('run-id must have 3 through 64 ASCII letters, digits, dash or underscore')
    if not re.fullmatch(DEVICE_PATTERN, args.device):
        parser.error('Select a specific owned emulator or simulator')
    with device_lock(args.device):
        return run_qualification(args, parser)


if __name__ == '__main__':
    raise SystemExit(main())
