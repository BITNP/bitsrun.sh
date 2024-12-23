#!/bin/bash
# bash version of https://github.com/BITNP/bitsrun, everything411, 2024, MIT License
# this script requires curl

fkbase64() {
    local encoded=$(base64 -w 0)
    local base64trans='LVoJPiCN2R8G90yg+hmFHuacZ1OWMnrsSTXkYpUq/3dlbfKwv6xztjI7DeBE45QA'
    local base64chars='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    local result=""
    for ((i=0; i<${#encoded}; i++)); do
        local current_char="${encoded:i:1}"
        if [ $current_char = '+' ]; then
            current_char='\+'
        fi
        local pos=$(expr index "$base64chars" "$current_char")
        if (( pos > 0 )); then
            local new_char="${base64trans:pos-1:1}"
            result+="$new_char"
        else
            result+="$current_char"
        fi
    done
    echo -n "$result"
}


ordat() {
    local msg="$1"
    local idx="$2"
    if [ ${#msg} -gt $idx ]; then
        printf "%d" "'${msg:$idx:1}"
    else
        echo -n 0
    fi
}

sencode() {
    local msg="$1"
    local msg_len=${#msg}
    local pwd=()

    for ((i=0; i<msg_len; i+=4)); do
        local combined=0
        combined=$(( ( $(ordat "$msg" $i) ) | ( $(ordat "$msg" $((i+1))) ) << 8 | ( $(ordat "$msg" $((i+2))) ) << 16 | ( $(ordat "$msg" $((i+3))) ) << 24 ))
        pwd+=($combined)
    done
    echo -n "${pwd[@]}"
}

sencode_len() {
    local msg="$1"
    echo -n $(sencode $msg) ${#msg}
}

lencode() {
    local msg="$@"
    for char in $msg; do
        local c=$(printf "%08x" "$char")
        c=${c:6:2}${c:4:2}${c:2:2}${c:0:2}
        echo -n $c | xxd -r -p
    done
}

xencode() {
    local msg="$1"
    local key="$2"

    if [ -z "$msg" ]; then
        echo ""
        return
    fi

    local pwd=($(sencode_len "$msg"))
    local pwdk=($(sencode "$key"))

    if [ ${#pwdk[@]} -lt 4 ]; then
        while [ ${#pwdk[@]} -lt 4 ]; do
            pwdk+=(0)
        done
    fi

    local n=$(( ${#pwd[@]} - 1 ))
    local z=${pwd[n]}
    local y=${pwd[0]}
    local c=2654435769
    local m=0
    local e=0
    local p=0
    local q=$(( 6 + 52 / (n + 1) ))
    local d=0

    while (( q > 0 )); do
        d=$(( (d + c) & 4294967295 ))
        e=$(( (d >> 2) & 3 ))
        p=0
        while (( p < n )); do
            y=${pwd[$((p+1))]}
            m=$(( (z >> 5) ^ (y << 2) ))
            m=$(( m + (( (y >> 3) ^ (z << 4)) ^ (d ^ y)) ))
            m=$(( m + (pwdk[(p & 3) ^ e] ^ z) ))
            pwd[p]=$(( (pwd[p] + m) & 4294967295 ))
            z=${pwd[p]}
            ((p++))
        done
        y=${pwd[0]}
        m=$(( (z >> 5) ^ (y << 2) ))
        m=$(( m + (( (y >> 3) ^ (z << 4)) ^ (d ^ y)) ))
        m=$(( m + (pwdk[((p & 3) ^ e)] ^ z) ))
        pwd[n]=$(( (pwd[n] + m) & 4294967295 ))
        z=${pwd[n]}
        ((q--))
    done
    lencode "${pwd[@]}"
}

get_json_value() {
  local json_string="$1"
  local key="$2"
  echo -n "$json_string" | grep -oP "\"${key}\" *: *\"[^\"]*\"" | sed -E "s/\"${key}\" *: *\"([^\"]*)\"/\1/"
}

urlencode() {
  local raw_string="$1"
  local encoded_string=""
  local i
  local c
  for ((i=0; i<${#raw_string}; i++)); do
    c="${raw_string:i:1}"
        if [[ "$c" =~ [a-zA-Z0-9~_.-] ]]; then
      encoded_string+="$c"
    else
      printf -v encoded_string "%s%%%02X" "$encoded_string" "'$c"
    fi
  done
  echo "$encoded_string"
}


API_BASE="http://10.0.0.55"

get_login_status() {
    local jsonp=$(curl -s "${API_BASE}/cgi-bin/rad_user_info?callback=jsonp")
    local usererror=$(get_json_value "$jsonp" "error")
    if [ $usererror = "not_online_error" ]; then
        echo -n $(get_json_value "$jsonp" "client_ip")
    else
        echo -n $(get_json_value "$jsonp" "online_ip") $(get_json_value "$jsonp" "user_name") online
    fi
}

get_token() {
    get_json_value "$(curl -s "${API_BASE}/cgi-bin/get_challenge?callback=jsonp&username=$1&ip=$2&")" "challenge"
}

get_acid() {
    local acid=$(curl -L -s http://t.tt | grep ac_id | sed -n 's/.*value="\([^"]*\)".*/\1/p')
    if [ -z "$acid" ]; then
        echo -n 1
    else
        echo $acid
    fi
}

login() {
    local username=$1
    local password=$2
    local ip=$3

    # get ac_id
    local acid=$(get_acid)
    # get srun token
    local token=$(get_token $username $ip)
    local token_md5=($(echo -n $token | md5sum))
    # prepare params
    local json_data="{\"username\":\"$username\",\"password\":\"$password\",\"acid\":\"$acid\",\"ip\":\"$ip\",\"enc_ver\":\"srun_bx1\"}"
    local info="{SRBX1}$(xencode "$json_data" "$token" | fkbase64 )"
    local checksum=($(echo -n "${token}${username}${token}${token_md5}${token}${acid}${token}${ip}${token}200${token}1${token}${info}" | sha1sum))
    local password_enc="{MD5}$token_md5"
    # urlencode params
    password_enc=$(urlencode "$password_enc")
    info=$(urlencode "$info")
    # call srun server
    local jsonp=$(curl -s "${API_BASE}/cgi-bin/srun_portal?callback=jsonp&action=login&username=$username&ac_id=$acid&ip=$ip&type=1&n=200&password=$password_enc&chksum=$checksum&info=$info")
    local usererror=$(get_json_value "$jsonp" "error")
    local srunmsg=$(get_json_value "$jsonp" "suc_msg")
    # result
    echo ${API_BASE} reports $usererror $srunmsg
}

logout() {
    local jsonp=$(curl -s "${API_BASE}/cgi-bin/srun_portal?callback=jsonp&action=logout")
    local usererror=$(get_json_value "$jsonp" "error")
    echo ${API_BASE} reports $usererror
}

if [ "$1" = "login" ]; then
    username=$2
    password=$3

    if [ -z "$username" ]; then
        echo "login requires username"
        exit 1
    fi

    login_status=$(get_login_status)
    if [[ "$login_status" =~ "online" ]]; then
        echo ${API_BASE} reports already online, stop
        exit 1
    fi
    if [ -z "$password" ]; then
        echo -n "password: "
        read -s password
        echo ""
    fi
    login "$username" "$password" $login_status
elif [ "$1" = "logout" ]; then
    logout
elif [ "$1" = "status" ]; then
    get_login_status
    echo ""
else
    echo "usage: login username [password]"
    echo "       logout"
    echo "       status"
    exit 1
fi

