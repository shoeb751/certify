## Certify

This is a tool that was build with the vision of having better SSL certificate management for an organisation that
handles a lot of domains while keeping the process for handling the certs manual

### Goals

The folowing goals are directly to be implemented in this project

1. Store SSL certs in a DB
2. Upload, List and download:
  * Certificates
    - Individual certificates
    - certificate chains (Download is available, Upload is to be implemented)
    - Full certificate chain (Download is available, Upload is to be implemented)
  * Keys
    - ~~Individual keys~~ (Downloading individual keys serves no purpose. We will always need a key associated with a cert to be used for deployment, uploading keys is implemented)
    - Keys pertaining to specific certificate
  * CSRs (To be implemented)
3. Interface for creation of CSR from a specific key (To be implemented)
4. Interface to list and download the above directly
5. Interface to upload certs,keys,zip files containing individual certs.

Side goals

1. Create a system for automated deployment of certs to places that will be using them (Given a file that knows the mappings)

### Development

1. Clone the project
2. run `docker-compose up --build`
3. Go to
   - localhost:7000 (Listing UI)
   - localhost:7001 (Adminer - to directly make changes to the DB)
4. To get get started with sample certs:
   - Generate Certs/keys etc using `openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365`
   - Upload the cert/key `curl http://127.0.0.1:7000/api/up --data-binary <path to cert/key>`
   - Check the interface on http://localhost:7000 or the api: `curl http://127.0.0.1:7000/api/list?type=cert`

Any kind of help is appreciated, just create an issue/MR.
I am using docker for development so that individual environments should not cause issues

### API
| API Endpoint |                 API Desc                  | Method |       Body(if any)        |    Query Parameters     | Query Param Values |                     Query Param Description                     |
|--------------|-------------------------------------------|--------|---------------------------|-------------------------|--------------------|-----------------------------------------------------------------|
| /api/up      | Upload cert/key/zip containing certs/keys | POST   | Binary data (crt,key,zip) |                         |                    |                                                                 |
| /api/list    | List uploaded certs                       | GET    |                           | all                     | true               | List all certs (including ones without key)                     |
|              |                                           |        |                           | issuer                  | true               | Add an "issuer" field to output data                            |
| /api/down    | Download certs,keys                       | GET    |                           | id (required if no dn)  | int                | Download cert with the corresponding id                         |
|              |                                           |        |                           | dn (required if no id) | <domain name>      | Download best match cert for the domain                         |
|              |                                           |        |                           | type                    | cert(defult)       | Download single cert                                            |
|              |                                           |        |                           |                         | key                | Download key corresponding to selected cert                     |
|              |                                           |        |                           |                         | fullchain          | Download a full chain cert (if all certs in chain are uploaded) |
|              |                                           |        |                           |                         | ic                 | Download Intermediate Cert                                      |


### Notes:

At the moment we rely on CN field to get the domains supported by cert.
We are not using the SAN field as the present approach is easier and
covers 99% of our current usecase.