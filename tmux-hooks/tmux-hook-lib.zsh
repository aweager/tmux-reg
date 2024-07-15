# tmux hooks to control server lifecycle

setopt err_exit
exec 2>&1

REG_RUNTIME_DIR="${XDG_RUNTIME_DIR-${XDG_CACHE_DIR-${HOME}/.cache}}/tmux/reg"
REG_STATE_DIR="${XDG_STATE_HOME-${HOME}/.local/state}/tmux/reg"
mkdir -p "$REG_STATE_DIR" "$REG_RUNTIME_DIR"
chmod 1700 "$REG_RUNTIME_DIR"

COMMAND_SERVER_CONFIG_DIR="${0:a:h}/../command-server"

function session-created() {
    # Start the server and configure the session
    local tmux_socket="$1"
    local session_id="$2"
    local tmux_pid="$3"
    local session_prefix="$tmux_pid.$session_id"

    local parent_socket="$REG_SOCKET"
    export REG_SOCKET="$REG_RUNTIME_DIR/$session_prefix.reg.sock"

    command-server-start \
        "${COMMAND_SERVER_CONFIG_DIR}/server.conf" \
        --socket "$REG_SOCKET" \
        --log-file "$REG_STATE_DIR/$session_prefix.server.log" \
        3> "$REG_STATE_DIR/$session_prefix.server.pid"

    tmux -S "$tmux_socket" \
        set-option -t "$session_id" @reg_socket "$REG_SOCKET" \;\
        set-option -t "$session_id" @reg_server_pid "$(cat "$REG_STATE_DIR/$session_prefix.server.pid")" \;\
        set-option -g "@reg_parent_socket_${session_id}" "$parent_socket" \;\
        set-environment -t "$session_id" REG_SOCKET "$REG_SOCKET" \;\
        set-option -t "$session_id" @reg_api_loaded 1

    # Session-level hooks
    tmux -S "$tmux_socket" \
        set-hook -t "$session_id" -a client-active "run-shell -b \"'#{@reg_bin}/client-active' '$session_id'\"" \;\
        set-hook -t "$session_id" -a client-detached "run-shell -b \"'#{@reg_bin}/client-detached' '$session_id'\""

    if [[ -n "$parent_socket" ]]; then
        reg -bb -I "$REG_SOCKET" sync "$parent_socket"
        reg -bb -I "$parent_socket" link "$REG_SOCKET"
        reg -bb -I "$REG_SOCKET" link "$parent_socket"
    fi
}

function client-active() {
    # Update which parent we sync with
    # REG_SOCKET was updated (or deleted) by tmux to match client env
    local session_id="$1"
    local new_parent="$REG_SOCKET"
    local old_parent="$(tmux display -p "#{@reg_parent_socket_${session_id}}")"
    export REG_SOCKET="$(tmux display -p '#{@reg_socket}')"

    tmux set-environment REG_SOCKET "$REG_SOCKET"


    if [[ "$old_parent" == "$new_parent" ]]; then
        # No need to adjust syncing
        return
    fi

    if [[ -n "$old_parent" ]]; then
        reg -I "$old_parent" unlink "$REG_SOCKET"
        reg -I "$REG_SOCKET" unlink "$old_parent"
    fi

    if [[ -n "$new_parent" ]]; then
        reg -bb -I "$REG_SOCKET" sync "$new_parent"
        reg -bb -I "$REG_SOCKET" link "$new_parent"
        reg -bb -I "$new_parent" link "$REG_SOCKET"
    fi

    tmux set-option -g "@reg_parent_socket_${session_id}" "$new_parent"
}

function client-detached() {
    # Unlink from parent
    local session_id="$1"
    local old_parent="$(tmux display -p "#{@reg_parent_socket_${session_id}}")"
    if [[ -z "$old_parent" ]]; then
        return
    fi

    reg -I "$old_parent" unlink "$REG_SOCKET"
    reg -I "$REG_SOCKET" unlink "$old_parent"
}

function session-closed() {
    # Bring down the server
    local session_id="$1"
    local tmux_pid="$2"
    local session_prefix="$tmux_pid.$session_id"
    local my_socket="$REG_RUNTIME_DIR/$session_prefix.reg.sock"

    local old_parent="$(tmux display -p "#{@reg_parent_socket_${session_id}}")"

    if [[ -n "$old_parent" ]]; then
        reg -I "$old_parent" unlink "$my_socket" &> /dev/null || true
    fi

    () {
        command-server-terminate "$my_socket"
        rm "$REG_STATE_DIR/$session_prefix.server.pid"
        rm "$REG_STATE_DIR/$session_prefix.server.log"
    } || true
}
