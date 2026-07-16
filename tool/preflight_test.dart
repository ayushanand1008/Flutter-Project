// =============================================================================
// Drive API Pre-Flight Test: drive.file Scope Subfolder Inheritance
// =============================================================================
// Tests whether User B (drive.file scope) can access subfolders created by
// User A inside a Picker-granted master folder WITHOUT a new Picker action.
//
// Auth: Uses googleapis_auth clientViaUserConsent — spins up a local loopback
//       HTTP server on an ephemeral port. No OOB / copy-paste flow.
//
// Usage: dart run preflight_test.dart
// =============================================================================

import 'dart:io';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

// ─── Credentials ─────────────────────────────────────────────────────────────
final _clientId = ClientId(
  'YOUR_GOOGLE_OAUTH_CLIENT_ID.apps.googleusercontent.com', // set via env or local config
  'YOUR_GOOGLE_OAUTH_CLIENT_SECRET', // set via env or local config
);

final _scopes = [drive.DriveApi.driveFileScope];

const _userAEmail = 'USER_A_EMAIL@gmail.com'; // replace with your account
const _userBEmail = 'USER_B_EMAIL@gmail.com'; // replace with partner's account

// ─── Test folder names ───────────────────────────────────────────────────────
String _isoDate() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

const _masterFolderName = 'Our_Scrapbook_Preflight';
final _subFolderName = '${_isoDate()}_Preflight_Test';
const _folderMime = 'application/vnd.google-apps.folder';

// ─── Result tracking ─────────────────────────────────────────────────────────
class TestResult {
  final String name;
  final bool passed;
  final String detail;
  const TestResult(this.name, this.passed, this.detail);
}

final _results = <TestResult>[];

void _section(String title) {
  print('\n' + '═' * 65);
  print('  $title');
  print('═' * 65);
}

void _record(String name, bool passed, String detail) {
  _results.add(TestResult(name, passed, detail));
  final icon = passed ? '✅ PASS' : '❌ FAIL';
  print('  $icon  [$name]\n        $detail');
}

// ─── Safe Windows URL launcher ────────────────────────────────────────────────
// Uses PowerShell Start-Process to correctly handle URLs with & characters.
// Falls back to just printing the URL if launch fails.
void _launchUrl(String url) {
  print('  ──────────────────────────────────────────────────────────');
  print('  Opening browser automatically...');
  print('  If the browser does NOT open, copy-paste this URL:\n');
  print('  $url\n');
  print('  ──────────────────────────────────────────────────────────');

  try {
    // PowerShell Start-Process handles special characters in URLs correctly.
    Process.runSync(
      'powershell',
      ['-NoProfile', '-Command', 'Start-Process', url],
    );
  } catch (_) {
    // Silently ignore — user can manually paste the URL printed above.
  }
}

// ─── OAuth helper ─────────────────────────────────────────────────────────────
// clientViaUserConsent spins up a loopback HTTP server automatically.
// No manual redirect URI needed in Google Cloud Console for Desktop clients.
Future<http.Client> _authenticate(String label) async {
  print('\n  Authenticating $label...');
  print('  Sign in as: $label');
  print('  If prompted with "Google hasn\'t verified this app":');
  print('  → Click "Advanced" → "Go to <app_name> (unsafe)" → Allow\n');

  final client = await clientViaUserConsent(
    _clientId,
    _scopes,
    _launchUrl,
  );

  print('\n  ✓ $label authenticated successfully.');
  return client;
}

// ─── Main ─────────────────────────────────────────────────────────────────────
void main() async {
  _section('DRIVE.FILE SCOPE PRE-FLIGHT TEST');
  print('  Master folder : $_masterFolderName');
  print('  Sub-folder    : $_subFolderName');
  print('  User A        : $_userAEmail');
  print('  User B        : $_userBEmail');
  print('  Scope         : ${_scopes.join(", ")}');

  String? masterFolderId;
  String? subFolderId;
  http.Client? clientA;

  // ───────────────────────────────────────────────────────────────────────────
  // PHASE 1 — USER A SETUP
  // ───────────────────────────────────────────────────────────────────────────
  _section('PHASE 1: Authenticate User A ($_userAEmail)');

  try {
    clientA = await _authenticate(_userAEmail);
  } catch (e) {
    print('\n  ❌ Authentication failed for User A: $e');
    exit(1);
  }

  final driveA = drive.DriveApi(clientA);

  // Step 1: Create master folder
  _section('STEP 1: User A creates master folder "$_masterFolderName"');
  try {
    final folder = drive.File()
      ..name = _masterFolderName
      ..mimeType = _folderMime;
    final created = await driveA.files.create(folder);
    masterFolderId = created.id!;
    _record('Create master folder', true,
        'Created "$_masterFolderName" (ID: $masterFolderId)');
  } catch (e) {
    _record('Create master folder', false, 'Exception: $e');
    print('\n  Cannot continue without master folder. Aborting.');
    clientA.close();
    exit(1);
  }

  // Step 2: Grant User B writer permission on master folder
  _section('STEP 2: User A grants User B writer access to master folder');
  try {
    final permission = drive.Permission()
      ..role = 'writer'
      ..type = 'user'
      ..emailAddress = _userBEmail;
    await driveA.permissions.create(
      permission,
      masterFolderId!,
      sendNotificationEmail: false,
    );
    _record('Grant User B writer permission', true,
        'Granted writer role to $_userBEmail on "$_masterFolderName"');
  } catch (e) {
    _record('Grant User B writer permission', false, 'Exception: $e');
  }

  // Step 3: Create subfolder inside master folder
  _section('STEP 3: User A creates subfolder "$_subFolderName"');
  try {
    final subFolder = drive.File()
      ..name = _subFolderName
      ..mimeType = _folderMime
      ..parents = [masterFolderId!];
    final created = await driveA.files.create(subFolder);
    subFolderId = created.id!;
    _record('Create subfolder', true,
        'Created "$_subFolderName" (ID: $subFolderId)');
  } catch (e) {
    _record('Create subfolder', false, 'Exception: $e');
    print('\n  Cannot continue without subfolder. Running cleanup.');
    await _cleanup(driveA, masterFolderId!);
    clientA.close();
    exit(1);
  }

  print('\n  ─── User A setup complete.');
  print('  ─── Master folder ID : $masterFolderId');
  print('  ─── Subfolder ID     : $subFolderId');

  // ───────────────────────────────────────────────────────────────────────────
  // PHASE 2 — USER B SCOPE INHERITANCE TEST
  // ───────────────────────────────────────────────────────────────────────────
  _section('PHASE 2: Authenticate User B ($_userBEmail)');
  print('  This simulates a fresh drive.file session with NO Picker action.');
  print('  User B will only authenticate via OAuth — no Picker will be shown.');

  http.Client? clientB;
  try {
    clientB = await _authenticate(_userBEmail);
  } catch (e) {
    print('\n  ❌ Authentication failed for User B: $e');
    await _cleanup(driveA, masterFolderId!);
    clientA.close();
    exit(1);
  }

  final driveB = drive.DriveApi(clientB);

  // Step 4: User B attempts files.list inside master folder (no Picker)
  _section('STEP 4: User B calls files.list inside master folder');
  print('  Query : \'$masterFolderId\' in parents and trashed = false');
  print('  Goal  : Verify subfolder is visible to User B without Picker\n');

  bool listSucceeded = false;
  try {
    final fileList = await driveB.files.list(
      q: "'$masterFolderId' in parents and trashed = false",
      $fields: 'files(id, name, mimeType)',
    );
    final files = fileList.files ?? [];
    if (files.isNotEmpty) {
      listSucceeded = true;
      _record('User B: files.list on master folder contents', true,
          'Returned ${files.length} item(s): ${files.map((f) => f.name).join(", ")}');
    } else {
      _record('User B: files.list on master folder contents', false,
          'Returned 0 items — subfolder NOT visible to User B under drive.file scope');
    }
  } on drive.DetailedApiRequestError catch (e) {
    _record('User B: files.list on master folder contents', false,
        'HTTP ${e.status}: ${e.message}');
  } catch (e) {
    _record('User B: files.list on master folder contents', false,
        'Exception: $e');
  }

  // Step 5: User B attempts files.get directly on the subfolder ID
  _section('STEP 5: User B calls files.get on subfolder ID directly');
  print('  Subfolder ID : $subFolderId');
  print('  Goal         : Verify direct ID access without Picker\n');

  bool getSucceeded = false;
  try {
    final file = await driveB.files.get(
      subFolderId!,
      $fields: 'id, name, mimeType, parents',
    ) as drive.File;
    getSucceeded = true;
    _record('User B: files.get on subfolder by ID', true,
        'Retrieved: name="${file.name}", id=${file.id}');
  } on drive.DetailedApiRequestError catch (e) {
    _record('User B: files.get on subfolder by ID', false,
        'HTTP ${e.status}: ${e.message}');
  } catch (e) {
    _record('User B: files.get on subfolder by ID', false, 'Exception: $e');
  }

  // ───────────────────────────────────────────────────────────────────────────
  // CLEANUP
  // ───────────────────────────────────────────────────────────────────────────
  _section('CLEANUP: Deleting test folders from Drive');
  await _cleanup(driveA, masterFolderId!);

  clientA.close();
  clientB.close();

  // ───────────────────────────────────────────────────────────────────────────
  // FINAL VERDICT
  // ───────────────────────────────────────────────────────────────────────────
  _section('FULL TEST REPORT');
  for (final r in _results) {
    final icon = r.passed ? '✅' : '❌';
    print('  $icon  ${r.name}');
    print('        ${r.detail}\n');
  }

  print('═' * 65);

  if (listSucceeded && getSucceeded) {
    print('''
  ╔═══════════════════════════════════════════════════════════╗
  ║  VERDICT: SCOPE INHERITANCE CONFIRMED ✅                  ║
  ║                                                           ║
  ║  User B\'s drive.file client CAN list and access          ║
  ║  subfolders created by User A inside the shared master    ║
  ║  folder — WITHOUT a new Picker action.                    ║
  ║                                                           ║
  ║  ACTION: Lock in drive.file scope. No escalation needed.  ║
  ╚═══════════════════════════════════════════════════════════╝''');
  } else if (listSucceeded || getSucceeded) {
    print('''
  ╔═══════════════════════════════════════════════════════════╗
  ║  VERDICT: PARTIAL INHERITANCE ⚠️                          ║
  ║                                                           ║
  ║  Some API calls succeeded but not all. Recommend          ║
  ║  escalating to full drive scope for reliable sync.        ║
  ╚═══════════════════════════════════════════════════════════╝''');
  } else {
    print('''
  ╔═══════════════════════════════════════════════════════════╗
  ║  VERDICT: SCOPE INHERITANCE FAILED ❌                     ║
  ║                                                           ║
  ║  User B CANNOT access partner-created subfolders under    ║
  ║  drive.file scope without a new Picker action.            ║
  ║                                                           ║
  ║  ACTION: Escalate to full drive scope.                    ║
  ║  Update backend.md Section 5 accordingly.                 ║
  ╚═══════════════════════════════════════════════════════════╝''');
  }
  print('═' * 65 + '\n');
}

// ─── Cleanup ──────────────────────────────────────────────────────────────────
Future<void> _cleanup(drive.DriveApi driveA, String folderId) async {
  try {
    // Deleting the master folder also cascades to the subfolder inside it.
    await driveA.files.delete(folderId);
    print('  ✓ Deleted test folder (ID: $folderId) from User A\'s Drive.');
  } catch (e) {
    print('  ⚠ Could not auto-delete test folder: $e');
    print('  Please manually delete "$_masterFolderName" from Google Drive.');
  }
}
