## Certify

This is a tool that was build with the vision of having better SSL certificate management for an organisation that
handles a lot of domains while keeping the process for handling the certs manual

### Goals

The folowing goals are directly to be implemented in this project

1. Store SSL certs in a DB
2. Upload, List and download:
  * Certificates
    - Individual certificates
    - certificate chains
  * Keys
    - ~~Individual keys~~ (Downloading individual keys serves no purpose. We will always need a key associated with a cert to be used for deployment)
    - Keys pertaining to specific cert
  * CSRs (To be implemented)
3. Interface for creation of CSR from a specific key (To be implemented)

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

The following APIs have been implemented:

```
Certify API:

* POST /api/up (TODO: name override for key)
  - Add cert or key (csr is to be implemented)
* GET /api/list
  - List the certs/keys in the DB
  - args:
    - type (optional)
      - cert (default)
      - key

* GET /api/down
  - download certs/keys/cert-chains from the DB
  - args
    - type (optional)
      - cert (default)
      - key (Will download key pertainig to the given cert id)
      - chain
    - id (required)
```
