import os,re

'''
Authors: Jessica Ribado and Eli Moss
Aim: A simple wrapper for metagenomics QC using paired end reads. To use this pipeline, edit parameters in the config.yaml, and specify the proper path to config file in the submission script.

This program runs under the assumption samples are named:
PREFIX_R1.fastq.gz and PREFIX_R2.fastq.gz.

This script will create the following folders:
PROJECT_DIR/qc/00_qc_reports/pre_fastqc
PROJECT_DIR/qc/00_qc_reports/post_fastqc
PROJECT_DIR/qc/01_trimmed
PROJECT_DIR/qc/02_dereplicate
PROJECT_DIR/qc/03_interleave

Run:
snakemake --jobs 100 \
		  -latency-wait 60 \
		  --configfile CONFIG_PATH/config.json \
		  --cluster-config CONFIG_PATH/clusterconfig.json \
		  --profile scg
'''

################################################################################
# specify project directories
DATA_DIR	= config["raw_reads_directory"]
PROJECT_DIR = config["output_directory"]

################################################################################
# get the names of the files in the directory
FILES = [f for f in os.listdir(DATA_DIR) if f.endswith(tuple(['fastq.gz', 'fq.gz']))]
SAMPLE_PREFIX = list(set([re.split('_1|_2', i)[0] for i in FILES]))

################################################################################
# specify which rules do not need to be submitted to the cluster
localrules:  interleave

rule all:
	input:
		expand(os.path.join(PROJECT_DIR, "qc/03_interleave_seqtk/{sample}.fastq"), sample=SAMPLE_PREFIX)

################################################################################
rule pre_fastqc:
	input: os.path.join(DATA_DIR, "{sample}_R{read}.fastq.gz")
	output: os.path.join(PROJECT_DIR,  "qc/00_qc_reports/pre_fastqc/{sample}_R{read}_fastqc.html")
	threads: 1
	shell: """
	   mkdir -p {PROJECT_DIR}/qc/00_qc_reports/pre_fastqc/
	   # module load java/latest
	   # module load fastqc/0.11.2
	   fastqc {input} --outdir {PROJECT_DIR}/qc/00_qc_reports/pre_fastqc/
	"""

################################################################################
rule trim_galore:
	input:
		fwd = os.path.join(DATA_DIR, "{sample}_1.fastq.gz"),
		rev = os.path.join(DATA_DIR, "{sample}_2.fastq.gz")
	output:
		fwd = os.path.join(PROJECT_DIR, "qc/01_trimmed/{sample}_1_val_1.fq.gz"),
		rev = os.path.join(PROJECT_DIR, "qc/01_trimmed/{sample}_2_val_2.fq.gz")
	threads: 4
	params:
		adaptor = config['trim_galore']['adaptors'],
		q_min   = config['trim_galore']['quality']
	shell: """
		 mkdir -p {PROJECT_DIR}/qc/01_trimmed/
		 # module load fastqc/0.11.2
		 # module load trim_galore/0.4.2
		 trim_galore --{params.adaptor} \
					 --quality {params.q_min} \
					 --output_dir {PROJECT_DIR}/qc/01_trimmed/ \
					 --paired {input.fwd} {input.rev}
	"""

# ################################################################################
# uses the old dereplication software, SuperDeduper that cannot be wrapped into a conda environment for ease. Seqkit is the conda friendly alternative.
# rule dereplicate:
# 	input:
# 	 	fwd = rules.trim_galore.output.fwd,
# 		rev = rules.trim_galore.output.rev
# 	output:
# 	 	fwd = os.path.join(PROJECT_DIR, "qc/02_dereplicate/{sample}_nodup_PE1.fastq"),
# 		rev = os.path.join(PROJECT_DIR, "qc/02_dereplicate/{sample}_nodup_PE2.fastq")
# 	threads: 2
# 	params:
# 		start	= config['dereplicate']['start_trim'],
# 		length	= config['dereplicate']['unique_length'],
# 		prefix	= "{sample}"
# 	shell: """
# 		{DEDUP_DIR}/super_deduper -1 {input.fwd} -2 {input.rev} \
# 			-p {PROJECT_DIR}/qc/02_dereplicate/{params.prefix} \
# 			-- start {params.start} \
# 			-- length {params.length}
# 		 """

################################################################################
rule dereplicate:
	input:
	 	fwd = rules.trim_galore.output.fwd,
		rev = rules.trim_galore.output.rev
	output:
	 	fwd = os.path.join(PROJECT_DIR, "qc/02_dereplicate/{sample}_nodup_PE1.fastq"),
		rev = os.path.join(PROJECT_DIR, "qc/02_dereplicate/{sample}_nodup_PE2.fastq")
	threads: 2
	params:
		start	= config['dereplicate']['start_trim'],
		prefix	= "{sample}"
	shell: """
		seqtk trimfq -b {params.start} {input.fwd}| seqtk rmdup > {output.fwd}
		seqtk trimfq -b {params.start} {input.rev}| seqtk rmdup > {output.rev}
	"""

################################################################################
rule post_fastqc:
	input:  rules.dereplicate.output
	output: os.path.join(PROJECT_DIR,  "qc/00_qc_reports/post_fastqc/{sample}_nodup_PE{read}_fastqc.html")
	threads: 1
	log: os.path.join(LOGS_DIR + "post_fastqc_{sample}_R{read}")
	shell: """
	   mkdir -p {PROJECT_DIR}/qc/00_qc_reports/post_fastqc/
	   # module load fastqc/0.11.2
	   fastqc {input} -f fastq --outdir {PROJECT_DIR}/qc/00_qc_reports/post_fastqc/
	 """


################################################################################
rule interleave:
	input:  rules.dereplicate.output
	output: os.path.join(PROJECT_DIR, "qc/03_interleave_seqtk/{sample}.fastq")
	params:
		prefix = "{sample}"
	shell: """
		mkdir -p {PROJECT_DIR}/qc/03_interleave_seqtk/
		# module load seqtk/1.2-r102
		seqtk mergepe {input} > {sample}.fastq
	"""
