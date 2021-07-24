#!/bin/sh
set -eu

############################################################
# 設定

print_usage_and_exit () {
    cat <<-USAGE 1>&2
		Usage   : ${0##*/} 今日の名言を表示する
		Options : -d[MMdd] 指定の日付の名言を表示する
		          -r ランダムな日付の名言を表示する
		Version :
		USAGE
    exit 1
}

# ランダムな日付を作成する際に必要な情報
# 2000年は閏年なのですべての日付を含む
# 2000/01/01 00:00 -> 946684800
# 2001/01/01 00:00 -> 978307200
ut_bgn=946684800
ut_end=978307200
ut_dlt=$((ut_end - ut_bgn))

# UNIX時間を日付に変換するためのawkスクリプト（2000年オンリー）
awkscript_ut2date='
  {
    t = $1

    s = t % (60      ); 
    m = t % (60*60   );
    h = t % (60*60*24);

    split("31 29 31 30 31 30 31 31 30 31 30 31", days_permonth);

    Y = 2000;
    M = 1;
    D = int(t / (60*60*24)) - 10957 + 1;
    for (;; M++) {
      if (D > days_permonth[M]) { D -= days_permonth[M]; } 
      else                      { break;                 }
    }
    
    printf("%04d%02d%02d%02d%02d%02d\n", Y,M,D,h,m,s);
  }
'

# 松下幸之助の名言が公開されているURL
url_template='https://www.panasonic.com/content/dam/panasonic/jp/corporate/history/founders-quotes/resource/DS<<date>>.HTML'

# （有効な）日付を表す拡張正規表現
reg_date=''
reg_date="${reg_date}"'(0[13578]|1[02])([0-2][0-9)|3[01])'
reg_date="${reg_date}"'|(0[469]|11)([0-2][0-9]|30)'
reg_date="${reg_date}"'|2([0-2][0-9])'

# HTTPコマンドの確認（POSIX標準外）
if   type wget 1>/dev/null 2>&1; then
  cmd_http='wget -q -O -'
elif type curl 1>/dev/null 2>&1; then
  cmd_http='curl -s'
else
  echo "${0##*/}: HTTP command not found" 1>&2
  exit 10
fi


############################################################
# パラメータを解釈

opt_d=''
opt_r=''

# 引数をパース
i=1
for arg in ${1+"$@"}
do
  case "$arg" in
    -h|--help|--version) print_usage_and_exit ;;
    -d*) opt_d=${arg#-d} ;;
    -r*) opt_r=yes       ;;
    *)                   ;;
  esac

  i=$((i + 1))
done

# 引数を評価（日付の指定）
if   [ -z "$opt_d" ]  ; then
  # 日付の指定がなければ今日の日付を設定
  opt_d=$(date '+%m%d')
elif printf '%s\n' "$opt_d" | grep -q -E "$reg_date"; then
  # 日付の指定があるかつ有効な日付である
  :
else
  # 日付の指定があるかつ無効な日付である
  echo "${0##*/}: \"$opt_d\" invalid date" 1>&2
  exit 20
fi

# 引数を評価（ランダムな日付の指定）
if   [ -z "$opt_r" ] ; then
  # ランダムな日付にしない
  :
else
  # ランダムな日付にする  
  opt_d=$(
    # 乱数を発生
    od -An -tu4 -N4 /dev/urandom                  |
    tr -d '\t '                                   |
    sed '/^$/d'                                   |

    # 2000/01/01~2000/12/31の間のUNIX時間に変換
    awk '{ print $1 % '"${ut_dlt}"' }'            |
    awk '{ print $1 + '"${ut_bgn}"' }'            |

    # UNIX時間を日付に変換
    awk "$awkscript_ut2date"                      |

    # 月日のみ抽出
    awk '{ print substr($1, 5, 4); }'             |

    cat
  )
fi

# パラメータを決定
date=$opt_d

############################################################

echo "$url_template"                                       |

# 指定の日付のURLを作成
sed 's/<<date>>/'"$date"'/'                                |

# ウェブページを取得
xargs $cmd_http                                            |

# ウェブページの文字コードがSJISなのでUTF8に変換
iconv -f sjis -t utf8                                      |

# 不要なHTMLの記述を削除
grep -e '^<p>' -e '^<h1>'                                  |

# HTMLタグを削除
sed 's!<[^>]*>!!g'                                         |

# 日付を削除
sed 's/　.*　//'                                           |

# 題目を強調
sed '1s/^.*$/【&】/'                                       |

cat
