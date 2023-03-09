import 'dart:async';

import 'package:chopper/chopper.dart';
import 'package:example/swagger_generated_code/client_index.dart';
import 'package:swagger_dart_code_generator/src/code_generators/v2/swagger_models_generator_v2.dart';
import 'package:swagger_dart_code_generator/src/code_generators/v3/swagger_models_generator_v3.dart';
import 'package:swagger_dart_code_generator/src/models/generator_options.dart';
import 'package:swagger_dart_code_generator/src/swagger_models/responses/swagger_schema.dart';
import 'package:swagger_dart_code_generator/src/swagger_models/swagger_root.dart';
import 'package:test/test.dart';

class MyInterceptor implements RequestInterceptor {
  final token = 'eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6Im9FVmMtcWJKTjJYWUkzejNzOTg5aCJ9.eyJodHRwczovL2ZvcmRlZmkuY29tL29yZ19pZCI6Im9yZ19pOVkzVVhrcnM4c1lSeTRwIiwiaHR0cHM6Ly9mb3JkZWZpLmNvbS9lbWFpbCI6ImRhdmlkQGZvcmRlZmkuY29tIiwiaXNzIjoiaHR0cHM6Ly9hdXRoLXN0YWdpbmcuc3RnLmFybmFjLmlvLyIsInN1YiI6Imdvb2dsZS1vYXV0aDJ8MTE2NzMyNzIxMzk3OTA1MjgxMTI2IiwiYXVkIjpbImh0dHBzOi8vYXBpLXN0YWdpbmcuc3RnLmFybmFjLmlvLyIsImh0dHBzOi8vZm9yZGVmaS1zdGFnaW5nLnVzLmF1dGgwLmNvbS91c2VyaW5mbyJdLCJpYXQiOjE2NzgzNTUyMzAsImV4cCI6MTY3ODQ0MTYzMCwiYXpwIjoiUXJMbWRlU1ZvSklvQUVLUTFmeUo0bjc5M1J3bXRyc24iLCJzY29wZSI6Im9wZW5pZCBwcm9maWxlIGVtYWlsIiwicGVybWlzc2lvbnMiOltdfQ.ABBVdudkfDFELfZJ8Q6lznrZm4WqQpQJv9H-AJ5ji3_iep6M2aBJc-FAR6SjomvzhKOB5e3g8cr_0u4KT6kdME3SaDZb7whoyWAY4r6DqFdOXA_ibqMvKeQ7QZq32YUUAYp0q75G-DctD6TRl1VUONOMaTYrZgvSG2ACY96cnyw2BZ7uBB3_-wnGpfMhlmejUomJscngvNeOsFhmK33DUc5WwoZxxG8tWuSI7YezfEFinKL_lCAP123iy4Un-D2bYwnGhUdCyIFJT78iRHVECkjZ1MHMpgYN-PvCHjUV2MyUUFXyuT9FTDPA7yJX3iFwwUCSsZqZkwajwjZQjpap0Q';
  // final token = 'Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6Im9FVmMtcWJKTjJYWUkzejNzOTg5aCJ9.eyJodHRwczovL2ZvcmRlZmkuY29tL29yZ19pZCI6Im9yZ19pOVkzVVhrcnM4c1lSeTRwIiwiaHR0cHM6Ly9mb3JkZWZpLmNvbS9lbWFpbCI6ImRhdmlkQGZvcmRlZmkuY29tIiwiaXNzIjoiaHR0cHM6Ly9hdXRoLXN0YWdpbmcuc3RnLmFybmFjLmlvLyIsInN1YiI6Imdvb2dsZS1vYXV0aDJ8MTE2NzMyNzIxMzk3OTA1MjgxMTI2IiwiYXVkIjpbImh0dHBzOi8vYXBpLXN0YWdpbmcuc3RnLmFybmFjLmlvLyIsImh0dHBzOi8vZm9yZGVmaS1zdGFnaW5nLnVzLmF1dGgwLmNvbS91c2VyaW5mbyJdLCJpYXQiOjE2NzgzNTUyMzAsImV4cCI6MTY3ODQ0MTYzMCwiYXpwIjoiUXJMbWRlU1ZvSklvQUVLUTFmeUo0bjc5M1J3bXRyc24iLCJzY29wZSI6Im9wZW5pZCBwcm9maWxlIGVtYWlsIiwicGVybWlzc2lvbnMiOltdfQ.ABBVdudkfDFELfZJ8Q6lznrZm4WqQpQJv9H-AJ5ji3_iep6M2aBJc-FAR6SjomvzhKOB5e3g8cr_0u4KT6kdME3SaDZb7whoyWAY4r6DqFdOXA_ibqMvKeQ7QZq32YUUAYp0q75G-DctD6TRl1VUONOMaTYrZgvSG2ACY96cnyw2BZ7uBB3_-wnGpfMhlmejUomJscngvNeOsFhmK33DUc5WwoZxxG8tWuSI7YezfEFinKL_lCAP123iy4Un-D2bYwnGhUdCyIFJT78iRHVECkjZ1MHMpgYN-PvCHjUV2MyUUFXyuT9FTDPA7yJX3iFwwUCSsZqZkwajwjZQjpap0Q';

  @override
  FutureOr<Request> onRequest(Request request) {
    request.headers['Authorization'] = 'Bearer $token';
    return request;
  }
}

void main() {

  // final baseUrl = 'https://api-staging.stg.arnac.io/redoc';
  final baseUrl = 'https://api-staging.stg.arnac.io/';
  final userId = '43aa201b-8063-48f9-be40-3478fc5fcc7b';

  // final auth = RequestInterceptor {
  //   @override
  //   FutureOr<Request> onRequest(Request request){
  //
  //   }
  // }

  final client = UsersOpenapi.create(
      baseUrl: Uri.parse(baseUrl),
      interceptors: [
        MyInterceptor(),
        // CustomUrlSetter(config: config),
        HttpLoggingInterceptor(),
      ]);


  group('run requests', () {
    test('test apiV1UsersInfoGet', () async {
      var apiV1UsersInfoGet = await client.apiV1UsersInfoGet();
      final str = apiV1UsersInfoGet.body.toString();
      print('apiV1UsersInfoGet json = $str');
      // expect(result, contains(expectedResult));
    });

    test('test apiV1UsersIdGet', () async {
      var apiV1UsersIdGet = await client.apiV1UsersIdGet(id: userId);
      final str = apiV1UsersIdGet.body.toString();
      print('apiV1UsersInfoGet json = $str');
      // expect(result, contains(expectedResult));
    });
  });
/* response should be like:
{
    "id": "43aa201b-8063-48f9-be40-3478fc5fcc7b",
    "created_at": "2023-01-29T14:13:44.048Z",
    "modified_at": "2023-02-26T15:50:54.216Z",
    "role": "admin",
    "user_type": "person",
    "name": "David Tsah",
    "email": "david@fordefi.com",
    "state": "active",
    "is_new_device_provisioning": false
}
*/

}
