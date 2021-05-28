# Immediate Goals for Certify

1. Allow for DB to be seperated from certify. DB details should be configurable so that mysql and nginx can be run seperately
2. Overhaul logging libray and allow for logging to local file via local nsq instance bundled with nginx (I do not have a better way of doing this in mind at the moment
  - Part 1 will be to overhaul the code to make logging more consistent
  - Part 2 will be to create adapters to direct logs (Eg. HTTP response, NSQ, something else)
