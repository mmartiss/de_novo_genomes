#!/bin/bash

cd ~/de_novo_genomes
cat SRR34323118.fastq | NanoFilt -q 17 -l 2500 > filtered_SRR34323118.fastqs