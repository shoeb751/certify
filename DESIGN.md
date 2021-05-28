# Design

I have thought about the following to make the codebase
easy to comprehend and to make unintended security bugs
difficult to exist.

The libs in lib folder will do all the heavy lifting regarding doing the processing.

Barring a few excetions, libs are not allowed to access ngx related datastructures unless a few are explicitly enabled

All ngx related access has to be there in either the landding
lua file, or in specialised libs built for specific functions.
This will allow for all calls to ngx to be wrapped around a neat function whose behaviour will be very limited.

This will also allow sanitisation of the input to prevent
unintended securoty bugs and allow making the codebase less
complicated at the same time.

Now, I just need to push these changes into the existing codebase.