#!/usr/bin/env bats

@test "_bl_log_error prints the correct format" {

  source "$HOME/git/bash-local/usr/share/bash-local/bash-local"

  run _bl_log_error "hello, world!"

  printf '%q\n' "$output"

  [ "$status" -eq 0 ]
  [ "$output" = "error: hello, world!" ]
}