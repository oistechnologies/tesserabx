## Signing in and MFA

Every agent account requires multi-factor authentication. The first time you sign in, you will enroll a TOTP-compatible authenticator app and receive recovery codes.

### Enrolling

1. Sign in with your email and password at `/agent/login`.
2. The system shows a QR code. Scan it with Google Authenticator, 1Password, Authy, or any RFC 6238 TOTP app.
3. Enter the six-digit code from the app to confirm the binding.
4. Save the **recovery codes** the system displays. Each code is single-use; use one if you lose your device and have not asked an admin to reset MFA.

### Signing in after enrollment

Each sign-in prompts for the current six-digit code from your app. The code rotates every 30 seconds; the system accepts the previous and next window to forgive clock drift.

### Lost your device

If you still have a recovery code, sign in with email + password, then enter the recovery code instead of a TOTP code. The code is consumed.

If you have lost both your device and your recovery codes, ask an administrator to reset your MFA. Open the **Users & roles** card under /agent/admin and select your account; an admin clicks **Reset MFA**. Your next sign-in restarts the enrollment flow.
