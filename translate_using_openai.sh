export PATH="$HOME/bilingual_book_maker:$PATH"
export file=$HOME/bilingual_book_maker/raw.txt
export output=$HOME/bilingual_book_maker/output.txt
pbpaste > ${file}
python3 $HOME/bilingual_book_maker/make_book.py --book_name ${file} --openai_key ${openai_key} --test --language "Traditional Chinese" > ${output}

# cat ${output} | pbcopy
cat ${output} | LC_CTYPE=UTF-8 pbcopy
