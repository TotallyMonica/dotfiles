# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH
export PATH="/home/mhanson/.local/bin:$PATH"

# Path to your oh-my-zsh installation.
ZSH=/home/mhanson/.oh-my-zsh/

# Set name of the theme to load. Optionally, if you set this to "random"
# it'll load a random theme each time that oh-my-zsh is loaded.
# See https://github.com/robbyrussell/oh-my-zsh/wiki/Themes
ZSH_THEME="garyblessington"

# Uncomment the following line to enable command auto-correction.
ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# The optional three formats: "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
HIST_STAMPS="dd/mm/yyyy"

## Plugins

# Completions
fpath+="${0:h}/src"

# Syntax Highlighting-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# First of all, ensure predictable parsing.
typeset zsh_highlight__aliases="$(builtin alias -Lm '[^+]*')"
# In zsh <= 5.2, aliases that begin with a plus sign ('alias -- +foo=42')
# are emitted by `alias -L` without a '--' guard, so they don't round trip.
#
# Hence, we exclude them from unaliasing:
builtin unalias -m '[^+]*'

# Set $0 to the expected value, regardless of functionargzero.
0=${(%):-%N}
if true; then
  # $0 is reliable
  if [[ $ZSH_HIGHLIGHT_REVISION == \$Format:* ]]; then
    # When running from a source tree without 'make install', $ZSH_HIGHLIGHT_REVISION
    # would be set to '$Format:%H$' literally.  That's an invalid value, and obtaining
    # the valid value (via `git rev-parse HEAD`, as Makefile does) might be costly, so:
    ZSH_HIGHLIGHT_REVISION=HEAD
  fi
fi

# This function takes a single argument F and returns True iff F is an autoload stub.
_zsh_highlight__function_is_autoload_stub_p() {
  if zmodload -e zsh/parameter; then
    #(( ${+functions[$1]} )) &&
    [[ "$functions[$1]" == *"builtin autoload -X"* ]]
  else
    #[[ $(type -wa -- "$1") == *'function'* ]] &&
    [[ "${${(@f)"$(which -- "$1")"}[2]}" == $'\t'$histchars[3]' undefined' ]]
  fi
  # Do nothing here: return the exit code of the if.
}

# Return True iff the argument denotes a function name.
_zsh_highlight__is_function_p() {
  if zmodload -e zsh/parameter; then
    (( ${+functions[$1]} ))
  else
    [[ $(type -wa -- "$1") == *'function'* ]]
  fi
}

# This function takes a single argument F and returns True iff F denotes the
# name of a callable function.
_zsh_highlight__function_callable_p() {
  if _zsh_highlight__is_function_p "$1" &&
     ! _zsh_highlight__function_is_autoload_stub_p "$1"
  then
    # Already fully loaded.
    return 0 # true
  else
    # "$1" is either an autoload stub, or not a function at all.
    #
    # Use a subshell to avoid affecting the calling shell.
    #
    # We expect 'autoload +X' to return non-zero if it fails to fully load
    # the function.
    ( autoload -U +X -- "$1" 2>/dev/null )
    return $?
  fi
}

# -------------------------------------------------------------------------------------------------
# Core highlighting update system
# -------------------------------------------------------------------------------------------------

# Use workaround for bug in ZSH?
# zsh-users/zsh@48cadf4 http://www.zsh.org/mla/workers//2017/msg00034.html
autoload -Uz is-at-least
if is-at-least 5.4; then
  typeset -g zsh_highlight__pat_static_bug=false
else
  typeset -g zsh_highlight__pat_static_bug=true
fi

# Array declaring active highlighters names.
typeset -ga ZSH_HIGHLIGHT_HIGHLIGHTERS

# Update ZLE buffer syntax highlighting.
#
# Invokes each highlighter that needs updating.
# This function is supposed to be called whenever the ZLE state changes.
_zsh_highlight()
{
  # Store the previous command return code to restore it whatever happens.
  local ret=$?
  # Make it read-only.  Can't combine this with the previous line when POSIX_BUILTINS may be set.
  typeset -r ret

  # $region_highlight should be predefined, either by zle or by the test suite's mock (non-special) array.
  (( ${+region_highlight} )) || {
    echo >&2 'zsh-syntax-highlighting: error: $region_highlight is not defined'
    echo >&2 'zsh-syntax-highlighting: (Check whether zsh-syntax-highlighting was installed according to the instructions.)'
    return $ret
  }

  # Probe the memo= feature, once.
  (( ${+zsh_highlight__memo_feature} )) || {
    region_highlight+=( " 0 0 fg=red, memo=zsh-syntax-highlighting" )
    case ${region_highlight[-1]} in
      ("0 0 fg=red")
        # zsh 5.8 or earlier
        integer -gr zsh_highlight__memo_feature=0
        ;;
      ("0 0 fg=red memo=zsh-syntax-highlighting")
        # zsh 5.9 or later
        integer -gr zsh_highlight__memo_feature=1
        ;;
      (" 0 0 fg=red, memo=zsh-syntax-highlighting") ;&
      (*)
        # We can get here in two ways:
        #
        # 1. When not running as a widget.  In that case, $region_highlight is
        # not a special variable (= one with custom getter/setter functions
        # written in C) but an ordinary one, so the third case pattern matches
        # and we fall through to this block.  (The test suite uses this codepath.)
        #
        # 2. When running under a future version of zsh that will have changed
        # the serialization of $region_highlight elements from their underlying
        # C structs, so that none of the previous case patterns will match.
        #
        # In either case, fall back to a version check.
        #
        # The memo= feature was added to zsh in commit zsh-5.8-172-gdd6e702ee.
        # The version number at the time was 5.8.0.2-dev (see Config/version.mk).
        # Therefore, on 5.8.0.3 and newer the memo= feature is available.
        #
        # On zsh version 5.8.0.2 between the aforementioned commit and the
        # first Config/version.mk bump after it (which, at the time of writing,
        # is yet to come), this condition will false negative.
        if is-at-least 5.8.0.3 $ZSH_VERSION.0.0; then
          integer -gr zsh_highlight__memo_feature=1
        else
          integer -gr zsh_highlight__memo_feature=0
        fi
        ;;
    esac
    region_highlight[-1]=()
  }

  # Reset region_highlight to build it from scratch
  if (( zsh_highlight__memo_feature )); then
    region_highlight=( "${(@)region_highlight:#*memo=zsh-syntax-highlighting*}" )
  else
    # Legacy codepath.  Not very interoperable with other plugins (issue #418).
    region_highlight=()
  fi

  # Remove all highlighting in isearch, so that only the underlining done by zsh itself remains.
  if [[ $WIDGET == zle-isearch-update ]] && { $zsh_highlight__pat_static_bug || ! (( $+ISEARCHMATCH_ACTIVE )) }; then
    return $ret
  fi

  # Before we 'emulate -L', save the user's options
  local -A zsyh_user_options
  if zmodload -e zsh/parameter; then
    zsyh_user_options=("${(kv)options[@]}")
  else
    local canonical_options onoff option raw_options
    raw_options=(${(f)"$(emulate -R zsh; set -o)"})
    canonical_options=(${${${(M)raw_options:#*off}%% *}#no} ${${(M)raw_options:#*on}%% *})
    for option in "${canonical_options[@]}"; do
      [[ -o $option ]]
      case $? in
        (0) zsyh_user_options+=($option on);;
        (1) zsyh_user_options+=($option off);;
        (*) # Can't happen, surely?
            echo "zsh-syntax-highlighting: warning: '[[ -o $option ]]' returned $?"
            ;;
      esac
    done
  fi
  typeset -r zsyh_user_options

  emulate -L zsh
  setopt localoptions warncreateglobal nobashrematch
  local REPLY # don't leak $REPLY into global scope

  # Do not highlight if there are more than 300 chars in the buffer. It's most
  # likely a pasted command or a huge list of files in that case..
  [[ -n ${ZSH_HIGHLIGHT_MAXLENGTH:-} ]] && [[ $#BUFFER -gt $ZSH_HIGHLIGHT_MAXLENGTH ]] && return $ret

  # Do not highlight if there are pending inputs (copy/paste).
  [[ $PENDING -gt 0 ]] && return $ret

  {
    local cache_place
    local -a region_highlight_copy

    # Select which highlighters in ZSH_HIGHLIGHT_HIGHLIGHTERS need to be invoked.
    local highlighter; for highlighter in $ZSH_HIGHLIGHT_HIGHLIGHTERS; do

      # eval cache place for current highlighter and prepare it
      cache_place="_zsh_highlight__highlighter_${highlighter}_cache"
      typeset -ga ${cache_place}

      # If highlighter needs to be invoked
      if ! type "_zsh_highlight_highlighter_${highlighter}_predicate" >&/dev/null; then
        echo "zsh-syntax-highlighting: warning: disabling the ${(qq)highlighter} highlighter as it has not been loaded" >&2
        # TODO: use ${(b)} rather than ${(q)} if supported
        ZSH_HIGHLIGHT_HIGHLIGHTERS=( ${ZSH_HIGHLIGHT_HIGHLIGHTERS:#${highlighter}} )
      elif "_zsh_highlight_highlighter_${highlighter}_predicate"; then

        # save a copy, and cleanup region_highlight
        region_highlight_copy=("${region_highlight[@]}")
        region_highlight=()

        # Execute highlighter and save result
        {
          "_zsh_highlight_highlighter_${highlighter}_paint"
        } always {
          : ${(AP)cache_place::="${region_highlight[@]}"}
        }

        # Restore saved region_highlight
        region_highlight=("${region_highlight_copy[@]}")

      fi

      # Use value form cache if any cached
      region_highlight+=("${(@P)cache_place}")

    done

    # Re-apply zle_highlight settings

    # region
    () {
      (( REGION_ACTIVE )) || return
      integer min max
      if (( MARK > CURSOR )) ; then
        min=$CURSOR max=$MARK
      else
        min=$MARK max=$CURSOR
      fi
      if (( REGION_ACTIVE == 1 )); then
        [[ $KEYMAP = vicmd ]] && (( max++ ))
      elif (( REGION_ACTIVE == 2 )); then
        local needle=$'\n'
        # CURSOR and MARK are 0 indexed between letters like region_highlight
        # Do not include the newline in the highlight
        (( min = ${BUFFER[(Ib:min:)$needle]} ))
        (( max = ${BUFFER[(ib:max:)$needle]} - 1 ))
      fi
      _zsh_highlight_apply_zle_highlight region standout "$min" "$max"
    }

    # yank / paste
    (( $+YANK_ACTIVE )) && (( YANK_ACTIVE )) && _zsh_highlight_apply_zle_highlight paste standout "$YANK_START" "$YANK_END"

    # isearch
    (( $+ISEARCHMATCH_ACTIVE )) && (( ISEARCHMATCH_ACTIVE )) && _zsh_highlight_apply_zle_highlight isearch underline "$ISEARCHMATCH_START" "$ISEARCHMATCH_END"

    # suffix
    (( $+SUFFIX_ACTIVE )) && (( SUFFIX_ACTIVE )) && _zsh_highlight_apply_zle_highlight suffix bold "$SUFFIX_START" "$SUFFIX_END"


    return $ret


  } always {
    typeset -g _ZSH_HIGHLIGHT_PRIOR_BUFFER="$BUFFER"
    typeset -gi _ZSH_HIGHLIGHT_PRIOR_CURSOR=$CURSOR
  }
}

# Apply highlighting based on entries in the zle_highlight array.
#    range. The order does not matter.
_zsh_highlight_apply_zle_highlight() {
  local entry="$1" default="$2"
  integer first="$3" second="$4"

  # read the relevant entry from zle_highlight
  local region="${zle_highlight[(r)${entry}:*]-}"

  if [[ -z "$region" ]]; then
    # entry not specified at all, use default value
    region=$default
  else
    # strip prefix
    region="${region#${entry}:}"

    # no highlighting when set to the empty string or to 'none'
    if [[ -z "$region" ]] || [[ "$region" == none ]]; then
      return
    fi
  fi

  integer start end
  if (( first < second )); then
    start=$first end=$second
  else
    start=$second end=$first
  fi
  region_highlight+=("$start $end $region, memo=zsh-syntax-highlighting")
}

# Array used by highlighters to declare user overridable styles.
typeset -gA ZSH_HIGHLIGHT_STYLES

# Whether the command line buffer has been modified or not.
#
# Returns 0 if the buffer has changed since _zsh_highlight was last called.
_zsh_highlight_buffer_modified()
{
  [[ "${_ZSH_HIGHLIGHT_PRIOR_BUFFER:-}" != "$BUFFER" ]]
}

# Whether the cursor has moved or not.
#
# Returns 0 if the cursor has moved since _zsh_highlight was last called.
_zsh_highlight_cursor_moved()
{
  [[ -n $CURSOR ]] && [[ -n ${_ZSH_HIGHLIGHT_PRIOR_CURSOR-} ]] && (($_ZSH_HIGHLIGHT_PRIOR_CURSOR != $CURSOR))
}

# Add a highlight defined by ZSH_HIGHLIGHT_STYLES.
#
# Should be used by all highlighters aside from 'pattern' (cf. ZSH_HIGHLIGHT_PATTERN).
# Overwritten in tests/test-highlighting.zsh when testing.
_zsh_highlight_add_highlight()
{
  local -i start end
  local highlight
  start=$1
  end=$2
  shift 2
  for highlight; do
    if (( $+ZSH_HIGHLIGHT_STYLES[$highlight] )); then
      region_highlight+=("$start $end $ZSH_HIGHLIGHT_STYLES[$highlight], memo=zsh-syntax-highlighting")
      break
    fi
  done
}

# Helper for _zsh_highlight_bind_widgets
# $1 is name of widget to call
_zsh_highlight_call_widget()
{
  builtin zle "$@" &&
  _zsh_highlight
}

# Decide whether to use the zle-line-pre-redraw codepath (colloquially known as
# "feature/redrawhook", after the topic branch's name) or the legacy "bind all
# widgets" codepath.
if is-at-least 5.8.0.2 $ZSH_VERSION.0.0 && _zsh_highlight__function_callable_p add-zle-hook-widget
then
  autoload -U add-zle-hook-widget
  _zsh_highlight__zle-line-finish() {
    # Reset $WIDGET since the 'main' highlighter depends on it.
    #
    # Since $WIDGET is declared by zle as read-only in this function's scope,
    # a nested function is required in order to shadow its built-in value;
    # see "User-defined widgets" in zshall.
    () {
      local -h -r WIDGET=zle-line-finish
      _zsh_highlight
    }
  }
  _zsh_highlight__zle-line-pre-redraw() {
    # Set $? to 0 for _zsh_highlight.  Without this, subsequent
    # zle-line-pre-redraw hooks won't run, since add-zle-hook-widget happens to
    # call us with $? == 1 in the common case.
    true && _zsh_highlight "$@"
  }
  _zsh_highlight_bind_widgets(){}
  if [[ -o zle ]]; then
    add-zle-hook-widget zle-line-pre-redraw _zsh_highlight__zle-line-pre-redraw
    add-zle-hook-widget zle-line-finish _zsh_highlight__zle-line-finish
  fi
else
  # Rebind all ZLE widgets to make them invoke _zsh_highlights.
  _zsh_highlight_bind_widgets()
  {
    setopt localoptions noksharrays
    typeset -F SECONDS
    local prefix=orig-s$SECONDS-r$RANDOM # unique each time, in case we're sourced more than once

    # Load ZSH module zsh/zleparameter, needed to override user defined widgets.
    zmodload zsh/zleparameter 2>/dev/null || {
      print -r -- >&2 'zsh-syntax-highlighting: failed loading zsh/zleparameter.'
      return 1
    }

    # Override ZLE widgets to make them invoke _zsh_highlight.
    local -U widgets_to_bind
    widgets_to_bind=(${${(k)widgets}:#(.*|run-help|which-command|beep|set-local-history|yank|yank-pop)})

    # Always wrap special zle-line-finish widget. This is needed to decide if the
    # current line ends and special highlighting logic needs to be applied.
    # E.g. remove cursor imprint, don't highlight partial paths, ...
    widgets_to_bind+=(zle-line-finish)

    # Always wrap special zle-isearch-update widget to be notified of updates in isearch.
    # This is needed because we need to disable highlighting in that case.
    widgets_to_bind+=(zle-isearch-update)

    local cur_widget
    for cur_widget in $widgets_to_bind; do
      case ${widgets[$cur_widget]:-""} in

        # Already rebound event: do nothing.
        user:_zsh_highlight_widget_*);;

        # The "eval"'s are required to make $cur_widget a closure: the value of the parameter at function
        # definition time is used.
        #
        # We can't use ${0/_zsh_highlight_widget_} because these widgets are always invoked with
        # NO_function_argzero, regardless of the option's setting here.

        # User defined widget: override and rebind old one with prefix "orig-".
        user:*) zle -N $prefix-$cur_widget ${widgets[$cur_widget]#*:}
                eval "_zsh_highlight_widget_${(q)prefix}-${(q)cur_widget}() { _zsh_highlight_call_widget ${(q)prefix}-${(q)cur_widget} -- \"\$@\" }"
                zle -N $cur_widget _zsh_highlight_widget_$prefix-$cur_widget;;

        # Completion widget: override and rebind old one with prefix "orig-".
        completion:*) zle -C $prefix-$cur_widget ${${(s.:.)widgets[$cur_widget]}[2,3]}
                      eval "_zsh_highlight_widget_${(q)prefix}-${(q)cur_widget}() { _zsh_highlight_call_widget ${(q)prefix}-${(q)cur_widget} -- \"\$@\" }"
                      zle -N $cur_widget _zsh_highlight_widget_$prefix-$cur_widget;;

        # Builtin widget: override and make it call the builtin ".widget".
        builtin) eval "_zsh_highlight_widget_${(q)prefix}-${(q)cur_widget}() { _zsh_highlight_call_widget .${(q)cur_widget} -- \"\$@\" }"
                 zle -N $cur_widget _zsh_highlight_widget_$prefix-$cur_widget;;

        # Incomplete or nonexistent widget: Bind to z-sy-h directly.
        *)
           if [[ $cur_widget == zle-* ]] && (( ! ${+widgets[$cur_widget]} )); then
             _zsh_highlight_widget_${cur_widget}() { :; _zsh_highlight }
             zle -N $cur_widget _zsh_highlight_widget_$cur_widget
           else
        # Default: unhandled case.
             print -r -- >&2 "zsh-syntax-highlighting: unhandled ZLE widget ${(qq)cur_widget}"
             print -r -- >&2 "zsh-syntax-highlighting: (This is sometimes caused by doing \`bindkey <keys> ${(q-)cur_widget}\` without creating the ${(qq)cur_widget} widget with \`zle -N\` or \`zle -C\`.)"
           fi
      esac
    done
  }
fi

# Load highlighters from directory.
#
# Arguments:
#   1) Path to the highlighters directory.
_zsh_highlight_load_highlighters()
{
  setopt localoptions noksharrays bareglobqual

  # Check the directory exists.
  [[ -d "$1" ]] || {
    print -r -- >&2 "zsh-syntax-highlighting: highlighters directory ${(qq)1} not found."
    return 1
  }

  # Load highlighters from highlighters directory and check they define required functions.
  local highlighter highlighter_dir
  for highlighter_dir ($1/*/(/)); do
    highlighter="${highlighter_dir:t}"
    [[ -f "$highlighter_dir${highlighter}-highlighter.zsh" ]] &&
      . "$highlighter_dir${highlighter}-highlighter.zsh"
    if type "_zsh_highlight_highlighter_${highlighter}_paint" &> /dev/null &&
       type "_zsh_highlight_highlighter_${highlighter}_predicate" &> /dev/null;
    then
        # New (0.5.0) function names
    elif type "_zsh_highlight_${highlighter}_highlighter" &> /dev/null &&
         type "_zsh_highlight_${highlighter}_highlighter_predicate" &> /dev/null;
    then
        # Old (0.4.x) function names
        if false; then
            # TODO: only show this warning for plugin authors/maintainers, not for end users
            print -r -- >&2 "zsh-syntax-highlighting: warning: ${(qq)highlighter} highlighter uses deprecated entry point names; please ask its maintainer to update it: https://github.com/zsh-users/zsh-syntax-highlighting/issues/329"
        fi
        # Make it work.
        eval "_zsh_highlight_highlighter_${(q)highlighter}_paint() { _zsh_highlight_${(q)highlighter}_highlighter \"\$@\" }"
        eval "_zsh_highlight_highlighter_${(q)highlighter}_predicate() { _zsh_highlight_${(q)highlighter}_highlighter_predicate \"\$@\" }"
    else
        print -r -- >&2 "zsh-syntax-highlighting: ${(qq)highlighter} highlighter should define both required functions '_zsh_highlight_highlighter_${highlighter}_paint' and '_zsh_highlight_highlighter_${highlighter}_predicate' in ${(qq):-"$highlighter_dir${highlighter}-highlighter.zsh"}."
    fi
  done
}

# Try binding widgets.
_zsh_highlight_bind_widgets || {
  print -r -- >&2 'zsh-syntax-highlighting: failed binding ZLE widgets, exiting.'
  return 1
}

# Resolve highlighters directory location.
_zsh_highlight_load_highlighters "${ZSH_HIGHLIGHT_HIGHLIGHTERS_DIR:-/home/mhanson/.highlighters}" || {
  print -r -- >&2 'zsh-syntax-highlighting: failed loading highlighters, exiting.'
  return 1
}

# Reset scratch variables when commandline is done.
_zsh_highlight_preexec_hook()
{
  typeset -g _ZSH_HIGHLIGHT_PRIOR_BUFFER=
  typeset -gi _ZSH_HIGHLIGHT_PRIOR_CURSOR=
}
autoload -Uz add-zsh-hook
add-zsh-hook preexec _zsh_highlight_preexec_hook 2>/dev/null || {
    print -r -- >&2 'zsh-syntax-highlighting: failed loading add-zsh-hook.'
  }

# Load zsh/parameter module if available
zmodload zsh/parameter 2>/dev/null || true

# Initialize the array of active highlighters if needed.
[[ $#ZSH_HIGHLIGHT_HIGHLIGHTERS -eq 0 ]] && ZSH_HIGHLIGHT_HIGHLIGHTERS=(main)

if (( $+X_ZSH_HIGHLIGHT_DIRS_BLACKLIST )); then
  print >&2 'zsh-syntax-highlighting: X_ZSH_HIGHLIGHT_DIRS_BLACKLIST is deprecated. Please use ZSH_HIGHLIGHT_DIRS_BLACKLIST.'
  ZSH_HIGHLIGHT_DIRS_BLACKLIST=($X_ZSH_HIGHLIGHT_DIRS_BLACKLIST)
  unset X_ZSH_HIGHLIGHT_DIRS_BLACKLIST
fi

# Restore the aliases we unned
eval "$zsh_highlight__aliases"
builtin unset zsh_highlight__aliases

# Set $?.
true

# Autosuggestions----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
#--------------------------------------------------------------------#
# Global Configuration Variables                                     #
#--------------------------------------------------------------------#

# Color to use when highlighting suggestion
# Uses format of `region_highlight`
# More info: http://zsh.sourceforge.net/Doc/Release/Zsh-Line-Editor.html#Zle-Widgets
(( ! ${+ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE} )) &&
typeset -g ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'

# Prefix to use when saving original versions of bound widgets
(( ! ${+ZSH_AUTOSUGGEST_ORIGINAL_WIDGET_PREFIX} )) &&
typeset -g ZSH_AUTOSUGGEST_ORIGINAL_WIDGET_PREFIX=autosuggest-orig-

# Strategies to use to fetch a suggestion
# Will try each strategy in order until a suggestion is returned
(( ! ${+ZSH_AUTOSUGGEST_STRATEGY} )) && {
  typeset -ga ZSH_AUTOSUGGEST_STRATEGY
  ZSH_AUTOSUGGEST_STRATEGY=(history)
}

# Widgets that clear the suggestion
(( ! ${+ZSH_AUTOSUGGEST_CLEAR_WIDGETS} )) && {
  typeset -ga ZSH_AUTOSUGGEST_CLEAR_WIDGETS
  ZSH_AUTOSUGGEST_CLEAR_WIDGETS=(
    history-search-forward
    history-search-backward
    history-beginning-search-forward
    history-beginning-search-backward
    history-substring-search-up
    history-substring-search-down
    up-line-or-beginning-search
    down-line-or-beginning-search
    up-line-or-history
    down-line-or-history
    accept-line
    copy-earlier-word
  )
}

# Widgets that accept the entire suggestion
(( ! ${+ZSH_AUTOSUGGEST_ACCEPT_WIDGETS} )) && {
  typeset -ga ZSH_AUTOSUGGEST_ACCEPT_WIDGETS
  ZSH_AUTOSUGGEST_ACCEPT_WIDGETS=(
    forward-char
    end-of-line
    vi-forward-char
    vi-end-of-line
    vi-add-eol
  )
}

# Widgets that accept the entire suggestion and execute it
(( ! ${+ZSH_AUTOSUGGEST_EXECUTE_WIDGETS} )) && {
  typeset -ga ZSH_AUTOSUGGEST_EXECUTE_WIDGETS
  ZSH_AUTOSUGGEST_EXECUTE_WIDGETS=(
  )
}

# Widgets that accept the suggestion as far as the cursor moves
(( ! ${+ZSH_AUTOSUGGEST_PARTIAL_ACCEPT_WIDGETS} )) && {
  typeset -ga ZSH_AUTOSUGGEST_PARTIAL_ACCEPT_WIDGETS
  ZSH_AUTOSUGGEST_PARTIAL_ACCEPT_WIDGETS=(
    forward-word
    emacs-forward-word
    vi-forward-word
    vi-forward-word-end
    vi-forward-blank-word
    vi-forward-blank-word-end
    vi-find-next-char
    vi-find-next-char-skip
  )
}

# Widgets that should be ignored (globbing supported but must be escaped)
(( ! ${+ZSH_AUTOSUGGEST_IGNORE_WIDGETS} )) && {
  typeset -ga ZSH_AUTOSUGGEST_IGNORE_WIDGETS
  ZSH_AUTOSUGGEST_IGNORE_WIDGETS=(
    orig-\*
    beep
    run-help
    set-local-history
    which-command
    yank
    yank-pop
    zle-\*
  )
}

# Pty name for capturing completions for completion suggestion strategy
(( ! ${+ZSH_AUTOSUGGEST_COMPLETIONS_PTY_NAME} )) &&
typeset -g ZSH_AUTOSUGGEST_COMPLETIONS_PTY_NAME=zsh_autosuggest_completion_pty

#--------------------------------------------------------------------#
# Utility Functions                                                  #
#--------------------------------------------------------------------#

_zsh_autosuggest_escape_command() {
  setopt localoptions EXTENDED_GLOB

  # Escape special chars in the string (requires EXTENDED_GLOB)
  echo -E "${1//(#m)[\"\'\\()\[\]|*?~]/\\$MATCH}"
}

#--------------------------------------------------------------------#
# Widget Helpers                                                     #
#--------------------------------------------------------------------#

_zsh_autosuggest_incr_bind_count() {
  typeset -gi bind_count=$((_ZSH_AUTOSUGGEST_BIND_COUNTS[$1]+1))
  _ZSH_AUTOSUGGEST_BIND_COUNTS[$1]=$bind_count
}

# Bind a single widget to an autosuggest widget, saving a reference to the original widget
_zsh_autosuggest_bind_widget() {
  typeset -gA _ZSH_AUTOSUGGEST_BIND_COUNTS

  local widget=$1
  local autosuggest_action=$2
  local prefix=$ZSH_AUTOSUGGEST_ORIGINAL_WIDGET_PREFIX

  local -i bind_count

  # Save a reference to the original widget
  case $widgets[$widget] in
    # Already bound
    user:_zsh_autosuggest_(bound|orig)_*)
      bind_count=$((_ZSH_AUTOSUGGEST_BIND_COUNTS[$widget]))
      ;;

    # User-defined widget
    user:*)
      _zsh_autosuggest_incr_bind_count $widget
      zle -N $prefix$bind_count-$widget ${widgets[$widget]#*:}
      ;;

    # Built-in widget
    builtin)
      _zsh_autosuggest_incr_bind_count $widget
      eval "_zsh_autosuggest_orig_${(q)widget}() { zle .${(q)widget} }"
      zle -N $prefix$bind_count-$widget _zsh_autosuggest_orig_$widget
      ;;

    # Completion widget
    completion:*)
      _zsh_autosuggest_incr_bind_count $widget
      eval "zle -C $prefix$bind_count-${(q)widget} ${${(s.:.)widgets[$widget]}[2,3]}"
      ;;
  esac

  # Pass the original widget's name explicitly into the autosuggest
  # function. Use this passed in widget name to call the original
  # widget instead of relying on the $WIDGET variable being set
  # correctly. $WIDGET cannot be trusted because other plugins call
  # zle without the `-w` flag (e.g. `zle self-insert` instead of
  # `zle self-insert -w`).
  eval "_zsh_autosuggest_bound_${bind_count}_${(q)widget}() {
    _zsh_autosuggest_widget_$autosuggest_action $prefix$bind_count-${(q)widget} \$@
  }"

  # Create the bound widget
  zle -N -- $widget _zsh_autosuggest_bound_${bind_count}_$widget
}

# Map all configured widgets to the right autosuggest widgets
_zsh_autosuggest_bind_widgets() {
  emulate -L zsh

  local widget
  local ignore_widgets

  ignore_widgets=(
    .\*
    _\*
    ${_ZSH_AUTOSUGGEST_BUILTIN_ACTIONS/#/autosuggest-}
    $ZSH_AUTOSUGGEST_ORIGINAL_WIDGET_PREFIX\*
    $ZSH_AUTOSUGGEST_IGNORE_WIDGETS
  )

  # Find every widget we might want to bind and bind it appropriately
  for widget in ${${(f)"$(builtin zle -la)"}:#${(j:|:)~ignore_widgets}}; do
    if [[ -n ${ZSH_AUTOSUGGEST_CLEAR_WIDGETS[(r)$widget]} ]]; then
      _zsh_autosuggest_bind_widget $widget clear
    elif [[ -n ${ZSH_AUTOSUGGEST_ACCEPT_WIDGETS[(r)$widget]} ]]; then
      _zsh_autosuggest_bind_widget $widget accept
    elif [[ -n ${ZSH_AUTOSUGGEST_EXECUTE_WIDGETS[(r)$widget]} ]]; then
      _zsh_autosuggest_bind_widget $widget execute
    elif [[ -n ${ZSH_AUTOSUGGEST_PARTIAL_ACCEPT_WIDGETS[(r)$widget]} ]]; then
      _zsh_autosuggest_bind_widget $widget partial_accept
    else
      # Assume any unspecified widget might modify the buffer
      _zsh_autosuggest_bind_widget $widget modify
    fi
  done
}

# Given the name of an original widget and args, invoke it, if it exists
_zsh_autosuggest_invoke_original_widget() {
  # Do nothing unless called with at least one arg
  (( $# )) || return 0

  local original_widget_name="$1"

  shift

  if (( ${+widgets[$original_widget_name]} )); then
    zle $original_widget_name -- $@
  fi
}

#--------------------------------------------------------------------#
# Highlighting                                                       #
#--------------------------------------------------------------------#

# If there was a highlight, remove it
_zsh_autosuggest_highlight_reset() {
  typeset -g _ZSH_AUTOSUGGEST_LAST_HIGHLIGHT

  if [[ -n "$_ZSH_AUTOSUGGEST_LAST_HIGHLIGHT" ]]; then
    region_highlight=("${(@)region_highlight:#$_ZSH_AUTOSUGGEST_LAST_HIGHLIGHT}")
    unset _ZSH_AUTOSUGGEST_LAST_HIGHLIGHT
  fi
}

# If there's a suggestion, highlight it
_zsh_autosuggest_highlight_apply() {
  typeset -g _ZSH_AUTOSUGGEST_LAST_HIGHLIGHT

  if (( $#POSTDISPLAY )); then
    typeset -g _ZSH_AUTOSUGGEST_LAST_HIGHLIGHT="$#BUFFER $(($#BUFFER + $#POSTDISPLAY)) $ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE"
    region_highlight+=("$_ZSH_AUTOSUGGEST_LAST_HIGHLIGHT")
  else
    unset _ZSH_AUTOSUGGEST_LAST_HIGHLIGHT
  fi
}

#--------------------------------------------------------------------#
# Autosuggest Widget Implementations                                 #
#--------------------------------------------------------------------#

# Disable suggestions
_zsh_autosuggest_disable() {
  typeset -g _ZSH_AUTOSUGGEST_DISABLED
  _zsh_autosuggest_clear
}

# Enable suggestions
_zsh_autosuggest_enable() {
  unset _ZSH_AUTOSUGGEST_DISABLED

  if (( $#BUFFER )); then
    _zsh_autosuggest_fetch
  fi
}

# Toggle suggestions (enable/disable)
_zsh_autosuggest_toggle() {
  if (( ${+_ZSH_AUTOSUGGEST_DISABLED} )); then
    _zsh_autosuggest_enable
  else
    _zsh_autosuggest_disable
  fi
}

# Clear the suggestion
_zsh_autosuggest_clear() {
  # Remove the suggestion
  unset POSTDISPLAY

  _zsh_autosuggest_invoke_original_widget $@
}

# Modify the buffer and get a new suggestion
_zsh_autosuggest_modify() {
  local -i retval

  # Only available in zsh >= 5.4
  local -i KEYS_QUEUED_COUNT

  # Save the contents of the buffer/postdisplay
  local orig_buffer="$BUFFER"
  local orig_postdisplay="$POSTDISPLAY"

  # Clear suggestion while waiting for next one
  unset POSTDISPLAY

  # Original widget may modify the buffer
  _zsh_autosuggest_invoke_original_widget $@
  retval=$?

  emulate -L zsh

  # Don't fetch a new suggestion if there's more input to be read immediately
  if (( $PENDING > 0 || $KEYS_QUEUED_COUNT > 0 )); then
    POSTDISPLAY="$orig_postdisplay"
    return $retval
  fi

  # Optimize if manually typing in the suggestion or if buffer hasn't changed
  if [[ "$BUFFER" = "$orig_buffer"* && "$orig_postdisplay" = "${BUFFER:$#orig_buffer}"* ]]; then
    POSTDISPLAY="${orig_postdisplay:$(($#BUFFER - $#orig_buffer))}"
    return $retval
  fi

  # Bail out if suggestions are disabled
  if (( ${+_ZSH_AUTOSUGGEST_DISABLED} )); then
    return $?
  fi

  # Get a new suggestion if the buffer is not empty after modification
  if (( $#BUFFER > 0 )); then
    if [[ -z "$ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE" ]] || (( $#BUFFER <= $ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE )); then
      _zsh_autosuggest_fetch
    fi
  fi

  return $retval
}

# Fetch a new suggestion based on what's currently in the buffer
_zsh_autosuggest_fetch() {
  if (( ${+ZSH_AUTOSUGGEST_USE_ASYNC} )); then
    _zsh_autosuggest_async_request "$BUFFER"
  else
    local suggestion
    _zsh_autosuggest_fetch_suggestion "$BUFFER"
    _zsh_autosuggest_suggest "$suggestion"
  fi
}

# Offer a suggestion
_zsh_autosuggest_suggest() {
  emulate -L zsh

  local suggestion="$1"

  if [[ -n "$suggestion" ]] && (( $#BUFFER )); then
    POSTDISPLAY="${suggestion#$BUFFER}"
  else
    unset POSTDISPLAY
  fi
}

# Accept the entire suggestion
_zsh_autosuggest_accept() {
  local -i retval max_cursor_pos=$#BUFFER

  # When vicmd keymap is active, the cursor can't move all the way
  # to the end of the buffer
  if [[ "$KEYMAP" = "vicmd" ]]; then
    max_cursor_pos=$((max_cursor_pos - 1))
  fi

  # If we're not in a valid state to accept a suggestion, just run the
  # original widget and bail out
  if (( $CURSOR != $max_cursor_pos || !$#POSTDISPLAY )); then
    _zsh_autosuggest_invoke_original_widget $@
    return
  fi

  # Only accept if the cursor is at the end of the buffer
  # Add the suggestion to the buffer
  BUFFER="$BUFFER$POSTDISPLAY"

  # Remove the suggestion
  unset POSTDISPLAY

  # Run the original widget before manually moving the cursor so that the
  # cursor movement doesn't make the widget do something unexpected
  _zsh_autosuggest_invoke_original_widget $@
  retval=$?

  # Move the cursor to the end of the buffer
  if [[ "$KEYMAP" = "vicmd" ]]; then
    CURSOR=$(($#BUFFER - 1))
  else
    CURSOR=$#BUFFER
  fi

  return $retval
}

# Accept the entire suggestion and execute it
_zsh_autosuggest_execute() {
  # Add the suggestion to the buffer
  BUFFER="$BUFFER$POSTDISPLAY"

  # Remove the suggestion
  unset POSTDISPLAY

  # Call the original `accept-line` to handle syntax highlighting or
  # other potential custom behavior
  _zsh_autosuggest_invoke_original_widget "accept-line"
}

# Partially accept the suggestion
_zsh_autosuggest_partial_accept() {
  local -i retval cursor_loc

  # Save the contents of the buffer so we can restore later if needed
  local original_buffer="$BUFFER"

  # Temporarily accept the suggestion.
  BUFFER="$BUFFER$POSTDISPLAY"

  # Original widget moves the cursor
  _zsh_autosuggest_invoke_original_widget $@
  retval=$?

  # Normalize cursor location across vi/emacs modes
  cursor_loc=$CURSOR
  if [[ "$KEYMAP" = "vicmd" ]]; then
    cursor_loc=$((cursor_loc + 1))
  fi

  # If we've moved past the end of the original buffer
  if (( $cursor_loc > $#original_buffer )); then
    # Set POSTDISPLAY to text right of the cursor
    POSTDISPLAY="${BUFFER[$(($cursor_loc + 1)),$#BUFFER]}"

    # Clip the buffer at the cursor
    BUFFER="${BUFFER[1,$cursor_loc]}"
  else
    # Restore the original buffer
    BUFFER="$original_buffer"
  fi

  return $retval
}

() {
  typeset -ga _ZSH_AUTOSUGGEST_BUILTIN_ACTIONS

  _ZSH_AUTOSUGGEST_BUILTIN_ACTIONS=(
    clear
    fetch
    suggest
    accept
    execute
    enable
    disable
    toggle
  )

  local action
  for action in $_ZSH_AUTOSUGGEST_BUILTIN_ACTIONS modify partial_accept; do
    eval "_zsh_autosuggest_widget_$action() {
      local -i retval

      _zsh_autosuggest_highlight_reset

      _zsh_autosuggest_$action \$@
      retval=\$?

      _zsh_autosuggest_highlight_apply

      zle -R

      return \$retval
    }"
  done

  for action in $_ZSH_AUTOSUGGEST_BUILTIN_ACTIONS; do
    zle -N autosuggest-$action _zsh_autosuggest_widget_$action
  done
}

#--------------------------------------------------------------------#
# Completion Suggestion Strategy                                     #
#--------------------------------------------------------------------#
# Fetches a suggestion from the completion engine
#

_zsh_autosuggest_capture_postcompletion() {
  # Always insert the first completion into the buffer
  compstate[insert]=1

  # Don't list completions
  unset 'compstate[list]'
}

_zsh_autosuggest_capture_completion_widget() {
  # Add a post-completion hook to be called after all completions have been
  # gathered. The hook can modify compstate to affect what is done with the
  # gathered completions.
  local -a +h comppostfuncs
  comppostfuncs=(_zsh_autosuggest_capture_postcompletion)

  # Only capture completions at the end of the buffer
  CURSOR=$#BUFFER

  # Run the original widget wrapping `.complete-word` so we don't
  # recursively try to fetch suggestions, since our pty is forked
  # after autosuggestions is initialized.
  zle -- ${(k)widgets[(r)completion:.complete-word:_main_complete]}

  if is-at-least 5.0.3; then
    # Don't do any cr/lf transformations. We need to do this immediately before
    # output because if we do it in setup, onlcr will be re-enabled when we enter
    # vared in the async code path. There is a bug in zpty module in older versions
    # where the tty is not properly attached to the pty slave, resulting in stty
    # getting stopped with a SIGTTOU. See zsh-workers thread 31660 and upstream
    # commit f75904a38
    stty -onlcr -ocrnl -F /dev/tty
  fi

  # The completion has been added, print the buffer as the suggestion
  echo -nE - $'\0'$BUFFER$'\0'
}

zle -N autosuggest-capture-completion _zsh_autosuggest_capture_completion_widget

_zsh_autosuggest_capture_setup() {
  # There is a bug in zpty module in older zsh versions by which a
  # zpty that exits will kill all zpty processes that were forked
  # before it. Here we set up a zsh exit hook to SIGKILL the zpty
  # process immediately, before it has a chance to kill any other
  # zpty processes.
  if ! is-at-least 5.4; then
    zshexit() {
      # The zsh builtin `kill` fails sometimes in older versions
      # https://unix.stackexchange.com/a/477647/156673
      kill -KILL $$ 2>&- || command kill -KILL $$

      # Block for long enough for the signal to come through
      sleep 1
    }
  fi

  # Try to avoid any suggestions that wouldn't match the prefix
  zstyle ':completion:*' matcher-list ''
  zstyle ':completion:*' path-completion false
  zstyle ':completion:*' max-errors 0 not-numeric

  bindkey '^I' autosuggest-capture-completion
}

_zsh_autosuggest_capture_completion_sync() {
  _zsh_autosuggest_capture_setup

  zle autosuggest-capture-completion
}

_zsh_autosuggest_capture_completion_async() {
  _zsh_autosuggest_capture_setup

  zmodload zsh/parameter 2>/dev/null || return # For `$functions`

  # Make vared completion work as if for a normal command line
  # https://stackoverflow.com/a/7057118/154703
  autoload +X _complete
  functions[_original_complete]=$functions[_complete]
  function _complete() {
    unset 'compstate[vared]'
    _original_complete "$@"
  }

  # Open zle with buffer set so we can capture completions for it
  vared 1
}

_zsh_autosuggest_strategy_completion() {
  # Reset options to defaults and enable LOCAL_OPTIONS
  emulate -L zsh

  # Enable extended glob for completion ignore pattern
  setopt EXTENDED_GLOB

  typeset -g suggestion
  local line REPLY

  # Exit if we don't have completions
  whence compdef >/dev/null || return

  # Exit if we don't have zpty
  zmodload zsh/zpty 2>/dev/null || return

  # Exit if our search string matches the ignore pattern
  [[ -n "$ZSH_AUTOSUGGEST_COMPLETION_IGNORE" ]] && [[ "$1" == $~ZSH_AUTOSUGGEST_COMPLETION_IGNORE ]] && return

  # Zle will be inactive if we are in async mode
  if zle; then
    zpty $ZSH_AUTOSUGGEST_COMPLETIONS_PTY_NAME _zsh_autosuggest_capture_completion_sync
  else
    zpty $ZSH_AUTOSUGGEST_COMPLETIONS_PTY_NAME _zsh_autosuggest_capture_completion_async "\$1"
    zpty -w $ZSH_AUTOSUGGEST_COMPLETIONS_PTY_NAME $'\t'
  fi

  {
    # The completion result is surrounded by null bytes, so read the
    # content between the first two null bytes.
    zpty -r $ZSH_AUTOSUGGEST_COMPLETIONS_PTY_NAME line '*'$'\0''*'$'\0'

    # Extract the suggestion from between the null bytes.  On older
    # versions of zsh (older than 5.3), we sometimes get extra bytes after
    # the second null byte, so trim those off the end.
    # See http://www.zsh.org/mla/workers/2015/msg03290.html
    suggestion="${${(@0)line}[2]}"
  } always {
    # Destroy the pty
    zpty -d $ZSH_AUTOSUGGEST_COMPLETIONS_PTY_NAME
  }
}

#--------------------------------------------------------------------#
# History Suggestion Strategy                                        #
#--------------------------------------------------------------------#
# Suggests the most recent history item that matches the given
# prefix.
#

_zsh_autosuggest_strategy_history() {
  # Reset options to defaults and enable LOCAL_OPTIONS
  emulate -L zsh

  # Enable globbing flags so that we can use (#m) and (x~y) glob operator
  setopt EXTENDED_GLOB

  # Escape backslashes and all of the glob operators so we can use
  # this string as a pattern to search the $history associative array.
  # - (#m) globbing flag enables setting references for match data
  # TODO: Use (b) flag when we can drop support for zsh older than v5.0.8
  local prefix="${1//(#m)[\\*?[\]<>()|^~#]/\\$MATCH}"

  # Get the history items that match the prefix, excluding those that match
  # the ignore pattern
  local pattern="$prefix*"
  if [[ -n $ZSH_AUTOSUGGEST_HISTORY_IGNORE ]]; then
    pattern="($pattern)~($ZSH_AUTOSUGGEST_HISTORY_IGNORE)"
  fi

  # Give the first history item matching the pattern as the suggestion
  # - (r) subscript flag makes the pattern match on values
  typeset -g suggestion="${history[(r)$pattern]}"
}

#--------------------------------------------------------------------#
# Match Previous Command Suggestion Strategy                         #
#--------------------------------------------------------------------#
# Suggests the most recent history item that matches the given
# prefix and whose preceding history item also matches the most
# recently executed command.
#
# For example, suppose your history has the following entries:
#   - pwd
#   - ls foo
#   - ls bar
#   - pwd
#
# Given the history list above, when you type 'ls', the suggestion
# will be 'ls foo' rather than 'ls bar' because your most recently
# executed command (pwd) was previously followed by 'ls foo'.
#
# Note that this strategy won't work as expected with ZSH options that don't
# preserve the history order such as `HIST_IGNORE_ALL_DUPS` or
# `HIST_EXPIRE_DUPS_FIRST`.

_zsh_autosuggest_strategy_match_prev_cmd() {
  # Reset options to defaults and enable LOCAL_OPTIONS
  emulate -L zsh

  # Enable globbing flags so that we can use (#m) and (x~y) glob operator
  setopt EXTENDED_GLOB

  # TODO: Use (b) flag when we can drop support for zsh older than v5.0.8
  local prefix="${1//(#m)[\\*?[\]<>()|^~#]/\\$MATCH}"

  # Get the history items that match the prefix, excluding those that match
  # the ignore pattern
  local pattern="$prefix*"
  if [[ -n $ZSH_AUTOSUGGEST_HISTORY_IGNORE ]]; then
    pattern="($pattern)~($ZSH_AUTOSUGGEST_HISTORY_IGNORE)"
  fi

  # Get all history event numbers that correspond to history
  # entries that match the pattern
  local history_match_keys
  history_match_keys=(${(k)history[(R)$~pattern]})

  # By default we use the first history number (most recent history entry)
  local histkey="${history_match_keys[1]}"

  # Get the previously executed command
  local prev_cmd="$(_zsh_autosuggest_escape_command "${history[$((HISTCMD-1))]}")"

  # Iterate up to the first 200 history event numbers that match $prefix
  for key in "${(@)history_match_keys[1,200]}"; do
    # Stop if we ran out of history
    [[ $key -gt 1 ]] || break

    # See if the history entry preceding the suggestion matches the
    # previous command, and use it if it does
    if [[ "${history[$((key - 1))]}" == "$prev_cmd" ]]; then
      histkey="$key"
      break
    fi
  done

  # Give back the matched history entry
  typeset -g suggestion="$history[$histkey]"
}

#--------------------------------------------------------------------#
# Fetch Suggestion                                                   #
#--------------------------------------------------------------------#
# Loops through all specified strategies and returns a suggestion
# from the first strategy to provide one.
#

_zsh_autosuggest_fetch_suggestion() {
  typeset -g suggestion
  local -a strategies
  local strategy

  # Ensure we are working with an array
  strategies=(${=ZSH_AUTOSUGGEST_STRATEGY})

  for strategy in $strategies; do
    # Try to get a suggestion from this strategy
    _zsh_autosuggest_strategy_$strategy "$1"

    # Ensure the suggestion matches the prefix
    [[ "$suggestion" != "$1"* ]] && unset suggestion

    # Break once we've found a valid suggestion
    [[ -n "$suggestion" ]] && break
  done
}

#--------------------------------------------------------------------#
# Async                                                              #
#--------------------------------------------------------------------#

_zsh_autosuggest_async_request() {
  zmodload zsh/system 2>/dev/null # For `$sysparams`

  typeset -g _ZSH_AUTOSUGGEST_ASYNC_FD _ZSH_AUTOSUGGEST_CHILD_PID

  # If we've got a pending request, cancel it
  if [[ -n "$_ZSH_AUTOSUGGEST_ASYNC_FD" ]] && { true <&$_ZSH_AUTOSUGGEST_ASYNC_FD } 2>/dev/null; then
    # Close the file descriptor and remove the handler
    exec {_ZSH_AUTOSUGGEST_ASYNC_FD}<&-
    zle -F $_ZSH_AUTOSUGGEST_ASYNC_FD

    # We won't know the pid unless the user has zsh/system module installed
    if [[ -n "$_ZSH_AUTOSUGGEST_CHILD_PID" ]]; then
      # Zsh will make a new process group for the child process only if job
      # control is enabled (MONITOR option)
      if [[ -o MONITOR ]]; then
        # Send the signal to the process group to kill any processes that may
        # have been forked by the suggestion strategy
        kill -TERM -$_ZSH_AUTOSUGGEST_CHILD_PID 2>/dev/null
      else
        # Kill just the child process since it wasn't placed in a new process
        # group. If the suggestion strategy forked any child processes they may
        # be orphaned and left behind.
        kill -TERM $_ZSH_AUTOSUGGEST_CHILD_PID 2>/dev/null
      fi
    fi
  fi

  # Fork a process to fetch a suggestion and open a pipe to read from it
  exec {_ZSH_AUTOSUGGEST_ASYNC_FD}< <(
    # Tell parent process our pid
    echo $sysparams[pid]

    # Fetch and print the suggestion
    local suggestion
    _zsh_autosuggest_fetch_suggestion "$1"
    echo -nE "$suggestion"
  )

  # There's a weird bug here where ^C stops working unless we force a fork
  # See https://github.com/zsh-users/zsh-autosuggestions/issues/364
  autoload -Uz is-at-least
  is-at-least 5.8 || command true

  # Read the pid from the child process
  read _ZSH_AUTOSUGGEST_CHILD_PID <&$_ZSH_AUTOSUGGEST_ASYNC_FD

  # When the fd is readable, call the response handler
  zle -F "$_ZSH_AUTOSUGGEST_ASYNC_FD" _zsh_autosuggest_async_response
}

# Called when new data is ready to be read from the pipe
# First arg will be fd ready for reading
# Second arg will be passed in case of error
_zsh_autosuggest_async_response() {
  emulate -L zsh

  local suggestion

  if [[ -z "$2" || "$2" == "hup" ]]; then
    # Read everything from the fd and give it as a suggestion
    IFS='' read -rd '' -u $1 suggestion
    zle autosuggest-suggest -- "$suggestion"

    # Close the fd
    exec {1}<&-
  fi

  # Always remove the handler
  zle -F "$1"
}

#--------------------------------------------------------------------#
# Start                                                              #
#--------------------------------------------------------------------#

# Start the autosuggestion widgets
_zsh_autosuggest_start() {
  # By default we re-bind widgets on every precmd to ensure we wrap other
  # wrappers. Specifically, highlighting breaks if our widgets are wrapped by
  # zsh-syntax-highlighting widgets. This also allows modifications to the
  # widget list variables to take effect on the next precmd. However this has
  # a decent performance hit, so users can set ZSH_AUTOSUGGEST_MANUAL_REBIND
  # to disable the automatic re-binding.
  if (( ${+ZSH_AUTOSUGGEST_MANUAL_REBIND} )); then
    add-zsh-hook -d precmd _zsh_autosuggest_start
  fi

  _zsh_autosuggest_bind_widgets
}

# Mark for auto-loading the functions that we use
autoload -Uz add-zsh-hook is-at-least

# Automatically enable asynchronous mode in newer versions of zsh. Disable for
# older versions because there is a bug when using async mode where ^C does not
# work immediately after fetching a suggestion.
# See https://github.com/zsh-users/zsh-autosuggestions/issues/364
if is-at-least 5.0.8; then
  typeset -g ZSH_AUTOSUGGEST_USE_ASYNC=
fi

# Start the autosuggestion widgets on the next precmd
add-zsh-hook precmd _zsh_autosuggest_start

# COLORS!!!
_zsh_256color_debug()
{
  [[ -n "${ZSH_256COLOR_DEBUG}" ]] && echo "zsh-256color: $@" >&2
}

_zsh_terminal_set_256color()
{
  if [[ "$TERM" =~ "-256color$" ]] ; then
    _zsh_256color_debug "256 color terminal already set."
    return
  fi

  local TERM256="${TERM}-256color"

  # Use (n-)curses binaries, if installed.
  if [[ -x "$( which toe )" ]] ; then
    if toe -a | egrep "^$TERM256" >/dev/null ; then
      _zsh_256color_debug "Found $TERM256 from (n-)curses binaries."
      export TERM="$TERM256"
      return
    fi
  fi

  # Search through termcap descriptions, if binaries are not installed.
  for termcaps in $TERMCAP "$HOME/.termcap" "/etc/termcap" "/etc/termcap.small" ; do
    if [[ -e "$termcaps" ]] && egrep -q "(^$TERM256|\|$TERM256)\|" "$termcaps" ; then
      _zsh_256color_debug "Found $TERM256 from $termcaps."
      export TERM="$TERM256"
      return
    fi
  done

  # Search through terminfo descriptions, if binaries are not installed.
  for terminfos in $TERMINFO "$HOME/.terminfo" "/etc/terminfo" "/lib/terminfo" "/usr/share/terminfo" ; do
    if [[ -e "$terminfos"/$TERM[1]/"$TERM256" || \
        -e "$terminfos"/"$TERM256" ]] ; then
      _zsh_256color_debug "Found $TERM256 from $terminfos."
      export TERM="$TERM256"
      return
    fi
  done
}

_zsh_terminal_set_256color
unset -f _zsh_terminal_set_256color
unset -f _zsh_256color_debug







## User configuration

# You may need to manually set your language environment
export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
export EDITOR='nano'

# Set Python version for cloudsdk
export CLOUDSDK_PYTHON=/usr/bin/python2

alias neofetch="neofetch --colors 0 0 0 162 255 121"

alias fetch="sh $HOME/scripts/fetch.sh"

alias grab_paper="sh $HOME/.i3/grab_paper.sh"

alias brightness="sh $HOME/scripts/brightness.sh"

alias cpf="python $HOME/cpf/cpf.py"

alias open_all="python $HOME/Python/open_all.py"

ZSH_CACHE_DIR=$HOME/.cache/oh-my-zsh
if [[ ! -d $ZSH_CACHE_DIR ]]; then
  mkdir $ZSH_CACHE_DIR
fi

fpath=(~/Projects/git_clones/zsh-completions/src $fpath)

source $ZSH/oh-my-zsh.sh

# Terminal with 256 colors
export LS_COLORS='no=00:fi=00:di=01;34:ln=01;36:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:ex=01;32:*.tar=01;31:*.tgz=01;31:*.arj=01;31:*.taz=01;31:*.lzh=01;31:*.zip=01;31:*.z=01;31:*.Z=01;31:*.gz=01;31:*.bz2=01;31:*.deb=01;31:*.rpm=01;31:*.jar=01;31:*.jpg=01;35:*.jpeg=01;35:*.gif=01;35:*.bmp=01;35:*.pbm=01;35:*.pgm=01;35:*.ppm=01;35:*.tga=01;35:*.xbm=01;35:*.xpm=01;35:*.tif=01;35:*.tiff=01;35:*.png=01;35:*.mov=01;35:*.mpg=01;35:*.mpeg=01;35:*.avi=01;35:*.fli=01;35:*.gl=01;35:*.dl=01;35:*.xcf=01;35:*.xwd=01;35:*.ogg=01;35:*.mp3=01;35:*.wav=01;35:'

#Server Variables
queerpi='pi@192.168.1.7'
virtmach='root@192.168.68.12'
truenas='root@192.168.68.11'
floppymech='monica@192.168.1.186'
bradleygal='monica@10.0.0.6'
linodesvr='root@45.33.10.75'
monicarose='root@monicarose.tech'
playground='mrhanson2@playground.bradley.edu'

#Server SSH aliases
alias queerpi="ssh $queerpi"
alias virtmach="ssh $virtmach"
alias truenas="ssh $truenas"
alias floppymech="ssh $floppymech"
alias bradleygal="ssh $bradleygal"
alias linodesvr="ssh $linodesvr"
alias monicarose="ssh $monicarose"
alias playground="ssh $playground"

#Quality of life changes
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias ls='ls --color=auto'

#Aliases
alias build='make -j$(nproc)'
alias youtube-dl='yt-dlp --format=mp4'
alias music-dl='youtube-dl --extract-audio --audio-format mp3'
alias untar='tar -xvf'
alias tarball='tar -czvf'
alias dupe='rsync -sazv --progress'
alias sshid='cat ~/.ssh/id_rsa.pub'
