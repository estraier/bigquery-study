#!/bin/bash

set -e

echo "Cleaning generated data..."

rm -f chatgpt_context.txt
rm -rf test/tmp
rm -rf test/expected
rm -rf test/diff

echo "Done."
