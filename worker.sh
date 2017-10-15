#!/bin/bash
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

echo
echo KOMENDY
echo ./worker.sh configure
echo ./worker.sh clear
echo ./worker.sh
echo 

if [ "$EUID" -ne 0 ]
then
    echo ERROR - brak uprawnien root
    exit
elif [ "$1" == "configure" ]
then
    chmod 711 .
    mkdir local
    exit
elif [ "$1" == "clear" ]
then
    rm zadanie &> /dev/null
    rm -rf local &> /dev/null
    rm -rf tmp &> /dev/null
    echo CZYSZCZENIE OK - potrzebna konfiguracja sprawdzarki
    exit
elif [ ! -e local ]
then
    echo ERROR - usuniety folder - wymagana konfguracja
    exit
fi

url=http://127.0.0.1/sprawdzarka/worker/response.php
while true;
do
    rm -rf tmp && mkdir tmp && chmod 777 tmp
    wget -T 10 -O tmp/request http://127.0.0.1/sprawdzarka/worker/getrequest.php 2> /dev/null
    echo Sprawdzam kolejkę
    if [ -e tmp/request ]
    then
        dane=(`cat tmp/request`)
        if [ ${dane[0]} -eq -1 ]
        then
            sleep 5
        else
                    zadanie=${dane[1]}
                    id=${dane[0]}
                    tester=${dane[2]}
                    echo Zadanie: $zadanie
                    echo Pobieram plik: $id
                    echo Tester: $tester
                    wget -T 10 -O tmp/zadanie.cpp http://127.0.0.1/sprawdzarka/files/$id.cpp 2> /dev/null
                    wget -T 10 -O tmp/tester.cpp http://127.0.0.1/sprawdzarka/tester/$tester.cpp 2> /dev/null
                    if [ -e tmp/zadanie.cpp ] && [ -e tmp/tester.cpp ]
                    then
                        echo Kompiluję
                        g++ -fmax-errors=2 -Wall -O2 -static -std=c++11 tmp/tester.cpp -lm -o tmp/tester &> /dev/null
                        if [ $? -ne 0 ]
                        then
                            info=`echo \`cat tmp/g++log.txt\` | base64`
                            info2=`echo \`cat tmp/g++out.txt\` | base64`
                            wget -T 10 -qO- "$url?zadanie=$zadanie&id=$id&status=5&info=$info&info2=$info2" &
                            echo Błąd kompilacji
                        fi
                        g++ -fmax-errors=2 -Wall -O2 -static -std=c++11 tmp/zadanie.cpp -lm -o tmp/zadanie 2>tmp/g++log.txt 1>tmp/g++out.txt
                        if [ $? -ne 0 ]
                        then
                            info=`echo \`cat tmp/g++log.txt\` | base64`
                            info2=`echo \`cat tmp/g++out.txt\` | base64`
                            wget -T 10 -qO- "$url?zadanie=$zadanie&id=$id&status=0&info=$info&info2=$info2" &
                            echo Błąd kompilacji
                        else
                            info=`echo \`cat tmp/g++log.txt\` | base64`
                            info2=`echo \`cat tmp/g++out.txt\` | base64`
                            mv tmp/zadanie .
                            mv tmp/tester .
                            nrtestu=0;
                            wget -T 10 -O tmp/pliki http://127.0.0.1/sprawdzarka/worker/getfiles.php?id=$zadanie 2> /dev/null
                            for i in `cat tmp/pliki`;
                            do
                                nazwain=$i.in
                                nazwaout=$i.out
                                if [ ! -e local/$nazwain ]
                                then
                                    wget -T 60 -O local/$nazwain http://127.0.0.1/sprawdzarka/files/$nazwain 2> /dev/null
                                    wget -T 60 -O local/$nazwaout http://127.0.0.1/sprawdzarka/files/$nazwaout 2> /dev/null
					                chmod 400 local/$nazwaout
                                fi
                                time1=`date +%s%3N`
                                nazwatmp=$nazwain su -- sprawdzarka -c 'ulimit -m 256000 && ulimit -v 256000 && ./zadanie < local/"$nazwatmp" > tmp/test1.out sprawdzarka || echo $? > tmp/exitcode.out' &
                                sleep 2.001 && pkill -u `id -u sprawdzarka` || echo $? > tmp/pkill2
                                time=$(($(date +%s%3N -r tmp/test1.out)-$time1))
                                echo $time
                                if [ -e tmp/pkill2 ]
                                then
                                    echo Na czas
                                    if [ -e tmp/exitcode.out ]
                                    then
                                        info3=`echo \`cat tmp/exitcode.out\` | base64`
                                        wget -T 10 -qO- "$url?test=$nrtestu&zadanie=$zadanie&id=$id&status=1&info=$info&info2=$info2&info3=$info3&time=$time" &
                                        echo Błąd wykonania
                                        rm tmp/exitcode.out;
                                    else
                                        echo Poprawne wykonanie
                                        ./tester tmp/test1.out local/$nazwaout local/$nazwain
                                        if [ $? -eq 0 ]
                                        then
                                            wget -T 10 -qO- "$url?test=$nrtestu&zadanie=$zadanie&id=$id&status=3&info=$info&info2=$info2&time=$time" &
                                            echo Poprawny wynik
                                        else
                                            wget -T 10 -qO- "$url?test=$nrtestu&zadanie=$zadanie&id=$id&status=4&info=$info&info2=$info2&time=$time" &
                                            echo Zła odpowiedź
                                        fi
                                        rm tmp/test1.out
                                    fi
                                    rm tmp/pkill2;
                                else
                                    wget -T 10 -qO- "$url?test=$nrtestu&zadanie=$zadanie&id=$id&status=2&info=$info&info2=$info2" &
                                    echo Za długo
                                fi
                                nrtestu=`expr 1 + $nrtestu`
                            done;
                            rm zadanie
                            rm tester
                        fi
                    else
                        echo Błąd pobierania
                    fi
        fi
    fi
    sleep 1
done;
