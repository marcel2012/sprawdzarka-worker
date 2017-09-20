#!/bin/bash
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

cd /home/pi/sprawdzarka-worker
sleep 30

mkdir remote
chmod a-rw remote
chmod u+r remote

curlftpfs 'user:pass!@serial.nazwa.pl/sprawdzarka/files/' remote
url=https://user:pass@serial.nazwa.pl/sprawdzarka/worker/response.php
while true;
do
    rm -rf tmp
    mkdir tmp
	chmod o+w tmp
    wget -T 10 -O tmp/getfile.php https://user:pass@serial.nazwa.pl/sprawdzarka/worker/getfile.php
    echo "Sprawdzam kolejkę"
    if [ -e tmp/getfile.php ]
    then
        if [ `cat tmp/getfile.php` -eq -1 ]
        then
            sleep 5
        else
            wget -T 10 -O tmp/getinfo.php https://user:pass@serial.nazwa.pl/sprawdzarka/worker/getinfo.php
            if [ -e tmp/getinfo.php ]
            then
                for i in `cat tmp/getinfo.php`;
                do
                    zadanie=$i
                done;
                    for i in `cat tmp/getfile.php`;
                    do
                        id=$i
                    done;
                    echo "Zadanie: $zadanie"
                    echo "Pobieram plik: $id"
                    cd tmp
                    wget -T 10 "https://user:pass@serial.nazwa.pl/sprawdzarka/files/$id.cpp"
                    cd ..
                    mv "tmp/$id.cpp" tmp/test1.cpp
                    if [ -e tmp/test1.cpp ]
                    then
                        echo "Kompiluję"
                        g++ -fmax-errors=2 -Wall -O2 -static -std=c++11 tmp/test1.cpp -lm -o tmp/test1 2>tmp/g++log.txt 1>tmp/g++out.txt
                        if [ $? -ne 0 ]
                        then
                            info=`echo \`cat tmp/g++log.txt\` | base64`
                            info2=`echo \`cat tmp/g++out.txt\` | base64`
                            wget -T 10 -qO- "$url?zadanie=$zadanie&id=$id&status=0&info=$info&info2=$info2" &
                            echo "Błąd kompilacji"
                        else
                            info=`echo \`cat tmp/g++log.txt\` | base64`
                            info2=`echo \`cat tmp/g++out.txt\` | base64`
                            mv tmp/test1 .
                            nrtestu=0;
                            for i in remote/data-"$zadanie"-*.in;
                            do
                                nazwain=${i:7}
                                nazwaout=`echo "$nazwain" | cut -d'.' -f 1`;
                                nazwaout="$nazwaout.out"
                                if [ ! -e local/"$nazwain" ]
                                then
                                    cd local
                                    wget -T 60 "https://user:pass@serial.nazwa.pl/sprawdzarka/files/$nazwain"
                                    wget -T 60 "https://user:pass@serial.nazwa.pl/sprawdzarka/files/$nazwaout"
					chmod a-r $nazwaout
					chmod u+r $nazwaout
                                    cd ..
                                fi
                                echo $i
                                time1=`date +%s%3N`
                                nazwatmp="$nazwain" su -- sprawdzarka -c 'ulimit -m 256000 && ulimit -v 256000 && ./test1 < "local/$nazwatmp" > tmp/test1.out sprawdzarka || echo $? > tmp/exitcode.out' &
                                sleep 0.501 && pkill -u 1001 || echo $? > tmp/pkill2
                                time=$(($(date +%s%3N -r tmp/test1.out)-$time1))
                                echo $time
                                if [ -e tmp/pkill2 ]
                                then
                                    echo "Na czas"
                                    if [ -e tmp/exitcode.out ]
                                    then
                                        info3=`echo \`cat tmp/exitcode.out\` | base64`
                                        wget -T 10 -qO- "$url?test=$nrtestu&zadanie=$zadanie&id=$id&status=1&info=$info&info2=$info2&info3=$info3&time=$time" &
                                        echo "Błąd wykonania"
                                        rm tmp/exitcode.out;
                                    else
                                        echo "Poprawne wykonanie"
                                        for j in `cat tmp/test1.out`;
                                        do
                                                printf "%d " $j >> tmp/test2.out
                                        done;
                                        for j in `cat local/$nazwaout`;
                                        do
                                                printf "%d " $j >> tmp/test3.out
                                        done;
                                        diff tmp/test2.out tmp/test3.out &> /dev/null
                                        if [ $? -eq 0 ]
                                        then
                                            wget -T 10 -qO- "$url?test=$nrtestu&zadanie=$zadanie&id=$id&status=3&info=$info&info2=$info2&time=$time" &
                                            echo "Poprawny wynik"
                                        else
                                            wget -T 10 -qO- "$url?test=$nrtestu&zadanie=$zadanie&id=$id&status=4&info=$info&info2=$info2&time=$time" &
                                            echo "Zła odpowiedź"
                                        fi
                                        rm tmp/test1.out
                                        rm tmp/test2.out
                                        rm tmp/test3.out
                                    fi
                                    rm tmp/pkill2;
                                else
                                    wget -T 10 -qO- "$url?test=$nrtestu&zadanie=$zadanie&id=$id&status=2&info=$info&info2=$info2" &
                                    echo "Za długo"
                                fi
                                nrtestu=`expr 1 + $nrtestu`
                            done;
                            rm test1
                        fi
                    else
                        echo "Błąd pobierania"
                    fi
            fi
        fi
    fi
    sleep 1
done;
