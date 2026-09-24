# Website to Mobile API Integration TODO

This checklist connects your existing Laravel website backend/database to the Flutter responder app.

## 1) Add API routing in Laravel bootstrap

File: c:/xampp/htdocs/rapid-alert/bootstrap/app.php

Update routing to include api:

- Add this argument inside withRouting(...):

api: __DIR__.'/../routes/api.php',

Current file only loads web/channels/commands.

## 2) Install and configure token auth (Sanctum)

Run in c:/xampp/htdocs/rapid-alert:

composer require laravel/sanctum
php artisan vendor:publish --provider="Laravel\Sanctum\SanctumServiceProvider"
php artisan migrate

Then update User model:

File: c:/xampp/htdocs/rapid-alert/app/Models/User.php
- Add use Laravel\Sanctum\HasApiTokens;
- Add trait to class: use HasApiTokens, HasFactory, Notifiable;

## 3) Add API login/logout for responder

Create controller:

File: c:/xampp/htdocs/rapid-alert/app/Http/Controllers/Api/AuthApiController.php

Endpoints needed:
- POST /api/auth/login
  - input: email, password
  - checks role == responder and is_active == true
  - returns: token, user
- POST /api/auth/logout
  - revoke current token

## 4) Create responder API routes

Create file:

File: c:/xampp/htdocs/rapid-alert/routes/api.php

Suggested route set (must be JSON only):

- POST /api/auth/login
- POST /api/auth/logout
- GET /api/responder/reports
- PUT /api/responder/reports/{report}/status
- GET /api/responder/reports/{report}/messages
- POST /api/responder/reports/{report}/messages
- GET /api/responder/reports/{report}/tracking
- POST /api/responder/reports/{report}/tracking
- GET /api/responder/coordination/events

Protect responder routes with auth:sanctum and role:responder.

## 5) Reuse existing logic from your current controllers

You already have the backend logic in web controllers:

- Assigned reports and status update:
  - App\Http\Controllers\AdminReportController
  - methods: responderQueueData, responderUpdate

- Chat and tracking:
  - App\Http\Controllers\DisasterCoordinationController
  - methods: messages, sendMessage, trackingLogs, storeTrackingLog

- Notifications/presence/history that can feed coordination stream:
  - App\Http\Controllers\DisasterCoordinationController
  - methods: notifications, history, responderPresence

Recommendation:
- Create a small API adapter controller (for example ResponderMobileApiController) that:
  - accepts path param {report}
  - maps to existing model/report ownership checks
  - returns stable JSON DTO fields for Flutter

## 6) Required JSON contracts for Flutter app

The Flutter API service expects these response bodies.

A. GET /api/responder/reports
{
  "reports": [
    {
      "reportId": 123,
      "trackingId": "RA-2026-0012",
      "hazardType": "Flood",
      "city": "Lipa City",
      "barangay": "Banaybanay",
      "reporterName": "A. Mendoza",
      "needHelp": true,
      "status": "in-progress",
      "latitude": 13.9420,
      "longitude": 121.1654,
      "updatedAt": 1750000000000
    }
  ]
}

B. PUT /api/responder/reports/{report}/status
request:
{
  "status": "in_progress"
}
response:
{
  "message": "Report updated successfully.",
  "report": { ... }
}

C. GET /api/responder/reports/{report}/messages
{
  "messages": [
    {
      "id": 1,
      "senderId": 45,
      "senderName": "Juan Dela Cruz",
      "receiverId": 60,
      "receiverName": "A. Mendoza",
      "message": "Team is on the way.",
      "createdAt": "2026-07-27T04:25:00Z"
    }
  ]
}

D. POST /api/responder/reports/{report}/messages
request:
{
  "message": "Stay in safe area."
}

E. POST /api/responder/reports/{report}/tracking
request:
{
  "latitude": 13.9412,
  "longitude": 121.1631
}

F. GET /api/responder/coordination/events
{
  "events": [
    {
      "id": "evt-1001",
      "title": "Live coordination update",
      "message": "Dispatch pulse from Banaybanay.",
      "priority": "urgent",
      "createdAt": "2026-07-27T04:27:00Z"
    }
  ]
}

## 7) CORS for mobile app

If Flutter app is not hosted under same domain, configure CORS.

Create/update:

File: c:/xampp/htdocs/rapid-alert/config/cors.php

Allow:
- paths: ['api/*']
- allowed_methods: ['*']
- allowed_origins: ['*'] (or your exact app origin)
- allowed_headers: ['*']

## 8) Test quickly with Postman first

1. POST /api/auth/login -> get token
2. GET /api/responder/reports with Bearer token
3. PUT status update
4. GET/POST messages
5. POST tracking updates

## 9) Enable Flutter API mode

In c:/Users/Jastin/StudioProjects/rapidalert run:

flutter run \
  --dart-define=RAPID_ALERT_USE_API=true \
  --dart-define=RAPID_ALERT_API_BASE_URL=http://10.0.2.2:8000 \
  --dart-define=RAPID_ALERT_TOKEN=YOUR_TOKEN \
  --dart-define=RAPID_ALERT_RESPONDER_USER_ID=YOUR_RESPONDER_USER_ID

Note:
- 10.0.2.2 is Android emulator localhost to your PC.
- Use your machine LAN IP for real devices.
