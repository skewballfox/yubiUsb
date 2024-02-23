# per instance
if status is-interactive
    command -sq zoxide; and zoxide init --cmd cd fish | source
    command -sq atuin; and atuin init fish | source
    #if type -q atuin
    #    set -gx ATUIN_NOBIND "true"
    #    atuin init fish | source
    #    bind \e\[A  _atuin_search_widget
    #    bind \e[1;2A  __atuin_history
    #end
    command -sq portmod; and register-python-argcomplete --shell fish portmod | source
end

if status is-login
    set -gx PATH $PATH /usr/local/sbin /usr/local/bin
end
# Aliases


alias ls "ls -1lih --color=auto"

alias grep "grep --color=auto"

# using starship as prompt
function fish_prompt
    starship init fish | source
end
