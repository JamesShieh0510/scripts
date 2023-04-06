#bash <(curl -s https://raw.githubusercontent.com/JamesShieh0510/scripts/master/install-openai-translator-and-ocr-tool.sh)
curl -O https://files.littlebird.com.au/ocr2.zip
unzip ocr2.zip
sudo cp ocr /usr/local/bin
cd $HOME
git clone https://github.com/yihong0618/bilingual_book_maker.git/
