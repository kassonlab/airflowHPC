#!/bin/bash -l

#SBATCH --job-name=airflow
#SBATCH --output=test_anthracene.o%j
#SBATCH --partition=small    # partition name
#SBATCH --nodes=1
#SBATCH --ntasks=32            # Total number of mpi tasks
#SBATCH --time=12:00:00       # Run time (d-hh:mm:ss)
#SBATCH --account=project_465001666  # Project for billing
#SBATCH --ntasks-per-node=32
#SBATCH --cpus-per-task=4

export SRUN_CPUS_PER_TASK=$SLURM_CPUS_PER_TASK
export OMP_PLACES=cores
export PREFIX=/project/project_465001666

cd $PREFIX

module load spack
module load cray-python
eval `spack load --sh   gromacs`
eval `spack load --sh   py-gmxapi`
eval `spack load --sh   postgresql`
source $PREFIX/airflowHPC_env/bin/activate
export AIRFLOW__CORE__EXECUTOR=airflowHPC.executors.resource_executor.ResourceExecutor
export AIRFLOW__CORE__LOAD_EXAMPLES=False
export AIRFLOW__CORE__DAGS_FOLDER="$PREFIX/airflowHPC/airflowHPC/dags/"
export AIRFLOW__HPC__CORES_PER_NODE=128
#export AIRFLOW__HPC__GPUS_PER_NODE=4
#export AIRFLOW__HPC__GPU_TYPE="nvidia"
export AIRFLOW__HPC__MEM_PER_NODE=256
export AIRFLOW__HPC__THREADS_PER_CORE=4
export AIRFLOW__SCHEDULER__USE_JOB_SCHEDULE=False
export RADICAL_UTILS_NO_ATFORK=1



# Handle case where non-default port number is used
portnum=$(grep -oP "^port = \K\d+" $PREFIX/postgresql_db/data/postgresql.conf)
if [ -n "$portnum" ]; then
	  echo "Port number is $portnum"
	    export AIRFLOW__DATABASE__SQL_ALCHEMY_CONN="postgresql+psycopg2://airflow_user:${AIRFLOWPASS}@localhost:$portnum/airflow_db"
	      pg_opts="-o \"-p $portnum\" -D $PREFIX/postgresql_db/data/ -l $PREFIX/postgresql_db/server.log"
      else
	        echo "Port number not found in postgresql_db/data/postgresql.conf"
		  export AIRFLOW__DATABASE__SQL_ALCHEMY_CONN="postgresql+psycopg2://airflow_user:${AIRFLOWPASS}@localhost/airflow_db"
		    pg_opts="-D $PREFIX/postgresql_db/data/ -l $PREFIX/postgresql_db/server.log"
fi

total_cores=$SLURM_NTASKS*$SLURM_CPUS_PER_TASK

#status=$(pg_ctl -D $PREFIX/postgresql_db/data/ -l $PREFIX/postgresql_db/server.log status)
status_cmd="pg_ctl $pg_opts status"
start_cmd="pg_ctl $pg_opts start"
status=$(eval $status_cmd)
if [[ "$status" == *"no server running"* ]]; then
	  echo "Starting PostgreSQL server"
	    #pg_ctl -D $PREFIX/postgresql_db/data/ -l $PREFIX/postgresql_db/server.log start
	      eval $start_cmd
      else
	        echo "PostgreSQL server is already running"
fi

airflow pools set default_pool 512 "default"


#module load gromacs
#source ~/gromacs/build2023.new/scripts/GMXRC.bash

#airflow dags backfill --reset-dagruns -y -s 2025-01-01 --conf='{"output_dir" : "test_anthracene"}' swarms
airflow dags unpause anthracene_simulation
airflow dags backfill --reset-dagruns -y -s 2025-01-01 anthracene_runner
