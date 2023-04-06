#bash <(curl -s https://raw.githubusercontent.com/JamesShieh0510/scripts/master/install-openai-translator-and-ocr-tool.sh)
# add shortcut: 
# 1. https://www.icloud.com/shortcuts/fa91687e481849d6a27ff873ec71599b
# 2. https://www.icloud.com/shortcuts/14d11971215f4d1bb20a6a8fd3bb3daa

curl -O https://files.littlebird.com.au/ocr2.zip
unzip ocr2.zip
sudo cp ocr /usr/local/bin
cd $HOME
git clone https://github.com/yihong0618/bilingual_book_maker.git/
