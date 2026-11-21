# teku_dun_api_client.api.WalkApi

## Load the API package
```dart
import 'package:teku_dun_api_client/api.dart';
```

All URIs are relative to *http://localhost*

Method | HTTP request | Description
------------- | ------------- | -------------
[**putLocation**](WalkApi.md#putlocation) | **PUT** /sessions/{session_id}/locations/{event_id} | Store or replay a location event
[**putSession**](WalkApi.md#putsession) | **PUT** /sessions/{session_id} | Create or replay a walking session
[**putSteps**](WalkApi.md#putsteps) | **PUT** /sessions/{session_id}/steps/{event_id} | Create or update a steps event


# **putLocation**
> putLocation(sessionId, eventId, locationRequest)

Store or replay a location event

Stores a location event for a walking session. The server records the time at which the request is received. Authentication is out of scope for this API contract. 

### Example
```dart
import 'package:teku_dun_api_client/api.dart';

final api = TekuDunApiClient().getWalkApi();
final String sessionId = sessionId_example; // String | Non-zero canonical UUID identifying the walking session.
final String eventId = eventId_example; // String | Non-zero canonical UUID identifying the immutable event record.
final LocationRequest locationRequest = ; // LocationRequest | 

try {
    api.putLocation(sessionId, eventId, locationRequest);
} catch on DioException (e) {
    print('Exception when calling WalkApi->putLocation: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **sessionId** | **String**| Non-zero canonical UUID identifying the walking session. | 
 **eventId** | **String**| Non-zero canonical UUID identifying the immutable event record. | 
 **locationRequest** | [**LocationRequest**](LocationRequest.md)|  | 

### Return type

void (empty response body)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **putSession**
> putSession(sessionId, sessionRequest)

Create or replay a walking session

Stores the start time for a walking session. The session identifier is supplied by the client and authentication is out of scope for this API contract. A session is the origin for one-minute step intervals; only the final partial interval is allowed by the client contract. The start time is immutable after the first accepted value. The server records the time at which the request is received. 

### Example
```dart
import 'package:teku_dun_api_client/api.dart';

final api = TekuDunApiClient().getWalkApi();
final String sessionId = sessionId_example; // String | Non-zero canonical UUID identifying the walking session.
final SessionRequest sessionRequest = ; // SessionRequest | 

try {
    api.putSession(sessionId, sessionRequest);
} catch on DioException (e) {
    print('Exception when calling WalkApi->putSession: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **sessionId** | **String**| Non-zero canonical UUID identifying the walking session. | 
 **sessionRequest** | [**SessionRequest**](SessionRequest.md)|  | 

### Return type

void (empty response body)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **putSteps**
> putSteps(sessionId, eventId, stepsRequest)

Create or update a steps event

Stores a one-minute steps interval measured from the session start. Clients send the final partial interval only when a session ends. Start and end times are immutable. A lower revision is a no-op, an equal revision with equal steps is a no-op, an equal revision with different steps is a conflict, and a higher revision updates the event. The server records the time at which the request is received. Authentication is out of scope for this API contract. 

### Example
```dart
import 'package:teku_dun_api_client/api.dart';

final api = TekuDunApiClient().getWalkApi();
final String sessionId = sessionId_example; // String | Non-zero canonical UUID identifying the walking session.
final String eventId = eventId_example; // String | Non-zero canonical UUID identifying the immutable event record.
final StepsRequest stepsRequest = ; // StepsRequest | 

try {
    api.putSteps(sessionId, eventId, stepsRequest);
} catch on DioException (e) {
    print('Exception when calling WalkApi->putSteps: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **sessionId** | **String**| Non-zero canonical UUID identifying the walking session. | 
 **eventId** | **String**| Non-zero canonical UUID identifying the immutable event record. | 
 **stepsRequest** | [**StepsRequest**](StepsRequest.md)|  | 

### Return type

void (empty response body)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

