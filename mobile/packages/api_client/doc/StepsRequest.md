# teku_dun_api_client.model.StepsRequest

## Load the model package
```dart
import 'package:teku_dun_api_client/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**startDatetime** | [**DateTime**](DateTime.md) | Immutable interval start in RFC 3339 format, aligned to a one-minute interval from the session origin. | 
**endDatetime** | [**DateTime**](DateTime.md) | Immutable interval end in RFC 3339 format. | 
**steps** | **int** | Non-negative step count. | 
**revision** | **int** | Client revision used for idempotent correction. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


