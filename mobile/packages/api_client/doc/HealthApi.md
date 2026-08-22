# teku_dun_api_client.api.HealthApi

## Load the API package
```dart
import 'package:teku_dun_api_client/api.dart';
```

All URIs are relative to *http://localhost*

Method | HTTP request | Description
------------- | ------------- | -------------
[**getHealthz**](HealthApi.md#gethealthz) | **GET** /healthz | Check whether the service is alive
[**getReadyz**](HealthApi.md#getreadyz) | **GET** /readyz | Check whether the service is ready


# **getHealthz**
> HealthResponse getHealthz()

Check whether the service is alive

Returns a successful response when the API process is alive.

### Example
```dart
import 'package:teku_dun_api_client/api.dart';

final api = TekuDunApiClient().getHealthApi();

try {
    final response = api.getHealthz();
    print(response);
} catch on DioException (e) {
    print('Exception when calling HealthApi->getHealthz: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**HealthResponse**](HealthResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getReadyz**
> ReadyResponse getReadyz()

Check whether the service is ready

Returns a successful response when the service can accept requests.

### Example
```dart
import 'package:teku_dun_api_client/api.dart';

final api = TekuDunApiClient().getHealthApi();

try {
    final response = api.getReadyz();
    print(response);
} catch on DioException (e) {
    print('Exception when calling HealthApi->getReadyz: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**ReadyResponse**](ReadyResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)
