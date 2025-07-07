#!/usr/bin/env bats

@test "register_user_commands preserves existing command aliases" {
    # Setup
    tmux set-option -g command-alias "foo=display 'bar'"
    
    # Act
    source scripts/commands.sh
    register_user_commands
    
    # Assert
    run tmux show-option -g command-alias
    echo "Output: $output" >&3
    [[ "$output" == *"foo=display 'bar'"* ]]
}