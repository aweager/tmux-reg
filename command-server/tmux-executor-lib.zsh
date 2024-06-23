#!/bin/zsh

source "$(dirname "$(whence -p reg)")/../lib/executor-lib.zsh"

function .get() {
    tmux save-buffer -b "reg_$1" - 2> /dev/null
}

function .list() {
    tmux list-buffers -f '#{?#{m:reg_*,#{buffer_name}},yes,}' -F '#{s|reg_||:buffer_name}'
}

function .set-no-sync() {
    tmux load-buffer -b "reg_$1" -
}

function .delete-no-sync() {
    tmux delete-buffer -b "reg_$1" 2> /dev/null
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
