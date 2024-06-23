# tmux hooks to control server lifecycle

setopt err_exit
exec 2>&1

REG_RUNTIME_DIR="${XDG_RUNTIME_DIR-${XDG_CACHE_DIR-${HOME}/.cache}}/tmux/reg"
REG_STATE_DIR="${XDG_STATE_HOME-${HOME}/.local/state}/tmux/reg"

COMMAND_SERVER_CONFIG_DIR="${0:a:h}/../command-server"

function session-created() {
    local session_id="$1"
    local tmux_pid="$2"
    local session_subdir="$tmux_pid/$session_id"

    mkdir -p "$REG_RUNTIME_DIR/$session_subdir" "$REG_STATE_DIR/$session_subdir"
    chmod 0700 "$REG_RUNTIME_DIR"

    local parent_socket="$REG_SOCKET"
    export REG_SOCKET="$REG_RUNTIME_DIR/$session_subdir/socket"

    command-server-start \
        "${COMMAND_SERVER_CONFIG_DIR}/server.conf" \
        --socket "$REG_SOCKET" \
        --log-file "$REG_STATE_DIR/$session_subdir/server.log" \
        3> "$REG_STATE_DIR/$session_subdir/server.pid"

    tmux set-option @reg_socket "$REG_SOCKET" \;\
         set-option @reg_server_pid "$(cat "$REG_STATE_DIR/$session_subdir/server.pid")" \;\
         set-option @reg_parent_socket "$parent_socket" \;\
         setenv REG_SOCKET "$REG_SOCKET"

    if [[ -n "$parent_socket" ]]; then
        reg -b -I "$REG_SOCKET" sync "$parent_socket"
        reg -b -I "$parent_socket" link "$REG_SOCKET"
        reg -b -I "$REG_SOCKET" link "$parent_socket"
    fi
}

function client-active() {
    local session_id="$(tmux display -p '#{session_id}')"
    local old_parent="$(tmux display -p '#{@reg_old_parent_socket}')"
    local new_parent="$(tmux display -p '#{@reg_parent_socket}')"

    if [[ "$old_parent" == "$new_parent" ]]; then
        # No need to adjust syncing
        return
    fi

    if [[ -n "$old_parent" ]]; then
        reg -I "$old_parent" unlink "$REG_SOCKET"
        reg -I "$REG_SOCKET" unlink "$old_parent"
    fi

    if [[ -n "$new_parent" ]]; then
        reg -b -I "$REG_SOCKET" sync "$new_parent"
        reg -b -I "$REG_SOCKET" link "$new_parent"
        reg -b -I "$new_parent" link "$REG_SOCKET"
    fi
}

function session-closed() {
    local session_id="$1"
    local tmux_pid="$2"
    local session_subdir="$tmux_pid/$session_id"

    setopt no_err_return no_err_exit

    () {
        command-server-terminate "$REG_RUNTIME_DIR/$session_subdir/socket"

        rm "$REG_RUNTIME_DIR/$session_subdir/socket" &> /dev/null
        rmdir "$REG_RUNTIME_DIR/$session_subdir"
        rmdir "$REG_RUNTIME_DIR/$tmux_pid" &> /dev/null

        rm "$REG_STATE_DIR/$session_subdir/server.pid"
        rm "$REG_STATE_DIR/$session_subdir/server.log"
        rmdir "$REG_STATE_DIR/$session_subdir"
        rmdir "$REG_STATE_DIR/$tmux_pid" &> /dev/null
    } || true
}