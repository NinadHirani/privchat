/// Public OAuth identifiers and user-facing strings for the sign-in flows.
///
/// Client IDs are public by design: they identify the app to Google during
/// sign-in and are not secrets. They must stay in sync with the OAuth client
/// registered in the Firebase console (Authentication > Settings > Authorized
/// domains and Google provider web client ID).
library;

/// The Firebase web app's OAuth client ID.
///
/// Needed explicitly on Android: without [kGoogleWebClientId] passed to
/// `GoogleSignIn`, google_sign_in cannot mint an ID token that Firebase
/// Authentication accepts, so Google sign-in fails with an invalid credential.
const String kGoogleWebClientId =
    '315683507801-spcvm4bnn50ea6sk38l95hum8r2phset.apps.googleusercontent.com';

/// Shown when Firebase failed to initialize and the sign-in options cannot run.
const String kSignInUnavailableMessage =
    'Sign-in options are unavailable right now because Firebase did not '
    'initialize. You can still use Pritoy with an offline identity.';
