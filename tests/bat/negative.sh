#!/bin/bash -e

echo "negative test stdout"
echo "negative test stderr" >&2
false
