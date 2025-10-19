Nera ena_download184650.log, nes per didelis, isskaidytas i chunks po 500000, 
ena_download_log direktorijoje <br />

$ grep "WARNING: No runs found for" ena_download184650.log | wc -l <br />

224

$ tail -n 1 ena_download184650.log <br />

CSV entries: 350

$ wc -l long_reads_to_download_biosample.tsv <br />

349 long_reads_to_download_biosample.tsv 


Trukstami, nerandami biosample SRA DB

$ grep -o 'SAMN[0-9]\+' not_found.csv > not_found_clean.csv <br />
$ grep -o 'SAMD[0-9]\+' not_found.csv >> not_found_clean.csv <br />
$ grep -o 'SAMEA[0-9]\+' not_found.csv >> not_found_clean.csv <br />

$ wc -l not_found_clean.csv <br />

224