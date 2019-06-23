#!/bin/bash

docker run --rm -it -v $(pwd):/src --workdir /src swift:5.0.1 /bin/bash
