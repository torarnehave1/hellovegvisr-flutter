# SMS Authentication Implementation for Hallo Vegvisr Flutter App

## Overview
Implemented SMS-based authentication (6-digit code) as an alternative to magic link authentication. The app now supports both authentication methods using the existing Vegvisr infrastructure.

## Backend Infrastructure (No New Endpoints Needed)
The required SMS/OTP endpoints already exist at `https://auth.vegvisr.org` and are used by the web app (vegvisr-frontend):

### Existing Endpoints Used

1. **Send SMS Code**
   - **Endpoint**: `POST /auth/phone/send-code`
   - **Body**: 
     ```json
     {
       "email": "user@example.com",
       "phone": "12345678"
     }
     ```
   - **Response**:
     ```json
     {
       "success": true,
       "expires_at": "2025-01-14T10:30:00Z"
     }
     ```

2. **Verify SMS Code**
   - **Endpoint**: `POST /auth/phone/verify-code`
   - **Body**:
     ```json
     {
       "email": "user@example.com",
       "code": "123456"
     }
     ```
   - **Response**:
     ```json
     {
       "success": true,
       "phone": "+4712345678",
       "user_id": "uuid"
     }
     ```

3. **Check Phone Status** (Optional)
   - **Endpoint**: `GET /auth/phone/status?email=user@example.com`
   - **Response**: Phone verification status for the user

## Flutter Implementation

### 1. Updated AuthService (`lib/services/auth_service.dart`)

Added three new methods:

```dart
/// Send 6-digit SMS verification code to user's phone
Future<Map<String, dynamic>?> sendOtpCode(String email, String phone) async

/// Verify 6-digit SMS code
Future<Map<String, dynamic>?> verifyOtpCode(String email, String code) async

/// Check phone verification status
Future<Map<String, dynamic>?> checkPhoneStatus(String email) async
```

**Key Features:**
- Uses `https://auth.vegvisr.org` for SMS endpoints (different from magic link endpoints)
- Returns structured response maps for error handling
- Saves phone number to SharedPreferences after successful verification

### 2. Updated LoginScreen UI (`lib/screens/login_screen.dart`)

#### New State Variables
- `_phoneController` - Phone number input field
- `_codeController` - 6-digit SMS code input field
- `_usePhoneAuth` - Toggle between magic link and SMS authentication
- Steps now include: `'email'` | `'magic'` | `'phone'` | `'code'`

#### New Methods
- `_sendSmsCode()` - Request SMS code from backend
- `_verifyOtpCode()` - Verify 6-digit code
- `_switchToPhoneAuth()` - Switch to SMS authentication
- `_switchToMagicLink()` - Switch back to magic link authentication

#### UI Flows

**Magic Link Flow (Default):**
1. Enter email → Click "Send Magic Link"
2. Receive magic link in email
3. Click link → App opens with token verified automatically
4. Option to "Or sign in with SMS code instead"

**SMS Flow:**
1. Click "Or sign in with SMS code instead"
2. Enter email (again) + phone number (8 digits, no country code)
3. Click "Send SMS Code"
4. Receive 6-digit code on phone
5. Enter code in 6-digit input field
6. Click "Verify Code"
7. Option to "Back to magic link"

### 3. Authentication Flow Diagram

```
┌─────────────────────────────────────┐
│         Login Screen (email)         │
└─────────────────────────────────────┘
                  │
        ┌─────────┴─────────┐
        ▼                   ▼
   Magic Link        SMS Code
      Flow             Flow
        │                 │
        ▼                 ▼
   Email → Code      Email + Phone → Code
        │                 │
        ▼                 ▼
   /magic/send      /phone/send-code
        │                 │
        ▼                 ▼
   Email Link        SMS Message
        │                 │
        ▼                 ▼
   Click Link        Enter 6 Digits
        │                 │
        ▼                 ▼
   Verify Token    /phone/verify-code
        │                 │
        └─────────┬───────┘
                  ▼
         Save User & Redirect
            to Home Screen
```

## Phone Number Format

- **Expected Format**: 8-digit Norwegian phone number (without +47 country code)
- **Example**: `12345678` (not `+4712345678`)
- **Input Constraint**: `maxLength: 8`, numeric only
- **Helper Text**: "Enter your phone number without country code"

## User Experience Improvements

1. **Cleaner UI**: 6-digit code is much simpler than copying/pasting long tokens
2. **Mobile-Friendly**: SMS codes can be auto-filled by device keyboard
3. **Flexibility**: Users can choose between magic link (email) or SMS (phone) authentication
4. **Quick Switch**: "Or sign in with SMS code instead" button allows toggling methods
5. **Clear Feedback**: Success/error messages guide users through the flow

## Differences from Web App

The web app (`vegvisr-frontend`) shows SMS flow after magic link fails or times out:
- Web: Magic link first → Falls back to SMS if not clicked
- Flutter: Users can choose SMS upfront or switch to it anytime

## Testing

### Manual Test Flow (SMS)

1. **Get a test account** (or create one):
   - Email: `test@example.com`
   - Phone: `12345678` (or any 8-digit number)

2. **Test SMS Code Flow**:
   - Launch app on Android device
   - Click "Or sign in with SMS code instead"
   - Enter email: `test@example.com`
   - Enter phone: `12345678`
   - Click "Send SMS Code"
   - Check phone for SMS with 6-digit code
   - Enter code and click "Verify Code"

3. **Expected Behavior**:
   - ✅ SMS received within 5-10 seconds
   - ✅ 6-digit code format in message
   - ✅ Code verification succeeds
   - ✅ App navigates to home screen
   - ✅ User email displayed on home screen
   - ✅ Logout works correctly

## Error Handling

The app handles these errors gracefully:

- **Invalid email**: "Please enter a valid email"
- **Invalid phone**: "Please enter a valid phone number (8 digits)"
- **Send code fails**: "Failed to send SMS code. Try again."
- **Invalid code**: "Invalid or expired code"
- **Code expired**: "Invalid or expired code" (codes expire after 30 minutes)

## Future Enhancements

1. **Phone pre-fill**: Check if user already has phone registered via `checkPhoneStatus()`
2. **Resend code timer**: Show countdown before allowing resend (already in web app)
3. **Rate limiting**: Prevent spam attempts (handled by backend)
4. **Multi-language SMS**: Support different languages (handled by backend)

## Related Files

- [lib/services/auth_service.dart](../../hellovegvisr-flutte/hallo_vegvisr/lib/services/auth_service.dart) - SMS endpoints
- [lib/screens/login_screen.dart](../../hellovegvisr-flutte/hallo_vegvisr/lib/screens/login_screen.dart) - SMS UI flows
- [lib/screens/home_screen.dart](../../hellovegvisr-flutte/hallo_vegvisr/lib/screens/home_screen.dart) - Post-auth home screen
- [vegvisr-frontend/src/views/LoginView.vue](../vegvisr-frontend/src/views/LoginView.vue#L450-L500) - Web app implementation reference

## Reference Implementation

The web app's LoginView.vue already implements this flow. Key differences in Flutter:
- No LinkedIn OAuth (yet)
- UI uses Flutter Material widgets instead of Vue
- Phone/code state managed with Flutter stateful widget instead of Vue refs
- SMS endpoints use the same backend as web app

## Architecture Notes

- **No new backend endpoints required** - Using existing auth.vegvisr.org infrastructure
- **Two independent auth methods** - Magic link and SMS can coexist
- **Backend already supports both** - Web app proof of concept
- **User choice** - Let users pick their preferred method
