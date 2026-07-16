import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:http/http.dart' as http;
import 'package:googleapis/drive/v3.dart' as drive;

class AuthService {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      drive.DriveApi.driveScope, // Full scope required to see folders created by partner's app
    ],
  );
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;

  // Stream to listen to Firebase Auth changes
  Stream<User?> get userChanges => _firebaseAuth.userChanges();

  // Get current Firebase user
  User? get currentUser => _firebaseAuth.currentUser;

  Future<UserCredential?> signIn() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null; // The user canceled the sign-in

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      return await _firebaseAuth.signInWithCredential(credential);
    } catch (e) {
      print("Error signing in with Google: $e");
      try {
        await _googleSignIn.disconnect();
      } catch (_) {}
      return null;
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _firebaseAuth.signOut();
  }

  Future<http.Client?> getAuthenticatedHttpClient() async {
    try {
      // Must ensure user is signed in to GoogleSignIn to get the authenticated client
      if (_googleSignIn.currentUser == null) {
        await _googleSignIn.signInSilently();
      }
      return await _googleSignIn.authenticatedClient();
    } catch (e) {
      print("Error getting authenticated HTTP client: \$e");
      return null;
    }
  }
}
