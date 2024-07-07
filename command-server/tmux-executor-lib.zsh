#!/bin/zsh

source "$(dirname "$(whence -p reg)")/../lib/executor-lib.zsh"

TMUX_SESSION_ID="$(tmux display -p '#{session_id}')"
TMUX_SESSION_ID="${TMUX_SESSION_ID#\$}"

function .get() {
    tmux save-buffer -b "reg${TMUX_SESSION_ID}_$1" - 2> /dev/null
}

function .list() {
    tmux list-buffers \
        -f "#{?#{m:reg${TMUX_SESSION_ID}_*,#{buffer_name}},yes,}" \
        -F "#{s|reg${TMUX_SESSION_ID}_||:buffer_name}"
}

function .set-no-sync() {
    tmux load-buffer -b "reg${TMUX_SESSION_ID}_$1" -
}

function .delete-no-sync() {
    tmux delete-buffer -b "reg${TMUX_SESSION_ID}_$1" 2> /dev/null
}

function .set-link-list() {
    tmux set-option @reg_links "${(kpj|:|)RegLinks}"
}

function .populate-links() {
    local REG_LINKS="$(tmux display-message -p '#{@reg_links}')"

    if [[ -z $REG_LINKS ]]; then
        RegLinks=()
        return
    fi

    RegLinks=()
    local link
    for link in "${(ps|:|)REG_LINKS}"; do
        RegLinks[$link]=1
    done
}
