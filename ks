#!/bin/sh

kustomize build "$@" --enable-helm | ./k apply -f -
