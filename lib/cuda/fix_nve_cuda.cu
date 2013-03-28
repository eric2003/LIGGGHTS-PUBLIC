/* ----------------------------------------------------------------------
   LAMMPS - Large-scale Atomic/Molecular Massively Parallel Simulator 

   Original Version:
   http://lammps.sandia.gov, Sandia National Laboratories
   Steve Plimpton, sjplimp@sandia.gov 

   See the README file in the top-level LAMMPS directory. 

   ----------------------------------------------------------------------- 

   USER-CUDA Package and associated modifications:
   https://sourceforge.net/projects/lammpscuda/ 

   Christian Trott, christian.trott@tu-ilmenau.de
   Lars Winterfeld, lars.winterfeld@tu-ilmenau.de
   Theoretical Physics II, University of Technology Ilmenau, Germany 

   See the README file in the USER-CUDA directory. 

   This software is distributed under the GNU General Public License.
------------------------------------------------------------------------- */

#include <stdio.h>
#define MY_PREFIX fix_nve_cuda
#define IncludeCommonNeigh
#include "cuda_shared.h"
#include "cuda_common.h"
#include "crm_cuda_utils.cu"
#include "fix_nve_cuda_cu.h"
#include "fix_nve_cuda_kernel.cu"

void Cuda_FixNVECuda_UpdateNmax(cuda_shared_data* sdata)
{
	#ifdef CUDA_USE_BINNING

		
		cudaMemcpyToSymbol(MY_CONST(bin_count_all)  , & sdata->atom.bin_count_all  .dev_data, sizeof(unsigned*));
		cudaMemcpyToSymbol(MY_CONST(bin_count_local), & sdata->atom.bin_count_local.dev_data, sizeof(unsigned*));
		cudaMemcpyToSymbol(MY_CONST(bin_dim)        , sdata->domain.bin_dim                 , sizeof(int)*3    );
		cudaMemcpyToSymbol(MY_CONST(binned_f)       , & sdata->atom.binned_f       .dev_data, sizeof(F_FLOAT*) );
		cudaMemcpyToSymbol(MY_CONST(binned_type)    , & sdata->atom.binned_type    .dev_data, sizeof(int*)     );
		cudaMemcpyToSymbol(MY_CONST(binned_v)       , & sdata->atom.binned_v       .dev_data, sizeof(V_FLOAT*) );
		cudaMemcpyToSymbol(MY_CONST(binned_x)       , & sdata->atom.binned_x       .dev_data, sizeof(X_FLOAT*) );
		cudaMemcpyToSymbol(MY_CONST(binned_rmass)   , & sdata->atom.binned_rmass   .dev_data, sizeof(V_FLOAT*) );
		cudaMemcpyToSymbol(MY_CONST(mask)           , & sdata->atom.mask           .dev_data, sizeof(int*)     );
		cudaMemcpyToSymbol(MY_CONST(rmass)          , & sdata->atom.rmass          .dev_data, sizeof(V_FLOAT*) );
		
	}
	
	#else
	
		cudaMemcpyToSymbol(MY_CONST(f)       , & sdata->atom.f    .dev_data, sizeof(F_FLOAT*) );
		cudaMemcpyToSymbol(MY_CONST(mask)    , & sdata->atom.mask .dev_data, sizeof(int*)     );
		cudaMemcpyToSymbol(MY_CONST(nlocal)  , & sdata->atom.nlocal        , sizeof(int)      );
		cudaMemcpyToSymbol(MY_CONST(nmax)    , & sdata->atom.nmax          , sizeof(int)      );
		cudaMemcpyToSymbol(MY_CONST(rmass)   , & sdata->atom.rmass.dev_data, sizeof(V_FLOAT*) );
		cudaMemcpyToSymbol(MY_CONST(mass)    , & sdata->atom.mass.dev_data , sizeof(V_FLOAT*) );
		cudaMemcpyToSymbol(MY_CONST(type)    , & sdata->atom.type .dev_data, sizeof(int*)     );
		cudaMemcpyToSymbol(MY_CONST(v)       , & sdata->atom.v    .dev_data, sizeof(V_FLOAT*) );
		cudaMemcpyToSymbol(MY_CONST(x)       , & sdata->atom.x    .dev_data, sizeof(X_FLOAT*) );
		cudaMemcpyToSymbol(MY_CONST(xhold)   , & sdata->atom.xhold.dev_data, sizeof(X_FLOAT*) ); //might be moved to a neighbor record in sdata
		cudaMemcpyToSymbol(MY_CONST(maxhold)   , & sdata->atom.maxhold, sizeof(int) ); //might be moved to a neighbor record in sdata
		cudaMemcpyToSymbol(MY_CONST(reneigh_flag), & sdata->buffer, sizeof(int*) ); //might be moved to a neighbor record in sdata
		cudaMemcpyToSymbol(MY_CONST(triggerneighsq), & sdata->atom.triggerneighsq, sizeof(X_FLOAT)); //might be moved to a neighbor record in sdata
	
	#endif
}

void Cuda_FixNVECuda_UpdateBuffer(cuda_shared_data* sdata)
{
		int size=(unsigned)10*sizeof(int);
		if(sdata->buffersize<size)
		{
			MYDBG(printf("Cuda_FixNVECuda Resizing Buffer at %p with %i kB to\n",sdata->buffer,sdata->buffersize);)
			CudaWrapper_FreeCudaData(sdata->buffer,sdata->buffersize);
			sdata->buffer = CudaWrapper_AllocCudaData(size);
			sdata->buffersize=size;
			sdata->buffer_new++;
			MYDBG(printf("New buffer at %p with %i kB\n",sdata->buffer,sdata->buffersize);)
			
		}
		cudaMemcpyToSymbol(MY_CONST(buffer) , & sdata->buffer, sizeof(int*)     );
		cudaMemcpyToSymbol(MY_CONST(reneigh_flag), & sdata->buffer, sizeof(int*) ); //might be moved to a neighbor record in sdata
}

void Cuda_FixNVECuda_Init(cuda_shared_data* sdata, X_FLOAT dtv, V_FLOAT dtf)
{
		cudaMemcpyToSymbol(MY_CONST(mass)    , & sdata->atom.mass.dev_data , sizeof(V_FLOAT*) );
		cudaMemcpyToSymbol(MY_CONST(dtf)     , & dtf                       		, sizeof(V_FLOAT)  );
		cudaMemcpyToSymbol(MY_CONST(dtv)     , & dtv                            , sizeof(X_FLOAT)  );
		cudaMemcpyToSymbol(MY_CONST(triggerneighsq), &sdata->atom.triggerneighsq, sizeof(X_FLOAT)  );
		cudaMemcpyToSymbol(MY_CONST(dist_check), & sdata->atom.dist_check       , sizeof(int)	   );
		cudaMemcpyToSymbol(MY_CONST(rmass_flag), & sdata->atom.rmass_flag       , sizeof(int)      ); //
		Cuda_FixNVECuda_UpdateNmax(sdata);
}


void Cuda_FixNVECuda_InitialIntegrate(cuda_shared_data* sdata, int groupbit, int mynlocal)//mynlocal can be nfirst if firstgroup==igroup  see cpp
{
	if(sdata->atom.update_nmax) 
		Cuda_FixNVECuda_UpdateNmax(sdata);
	if(sdata->atom.update_nlocal) 		
		cudaMemcpyToSymbol(MY_CONST(nlocal)  , & sdata->atom.nlocal , sizeof(int)); 
	if(sdata->buffer_new)
		Cuda_FixNVECuda_UpdateBuffer(sdata);

	#ifdef CUDA_USE_BINNING
	
	dim3 grid(sdata->domain.bin_dim[0], sdata->domain.bin_dim[1] * sdata->domain.bin_neighbors[2], 1);
	dim3 threads(sdata->domain.bin_nmax, 1, 1);
	FixNVECuda_InitialIntegrate_N_Kernel<<<grid, threads>>> (groupbit);
	cudaThreadSynchronize();
	CUT_CHECK_ERROR("Cuda_FixNVECuda_InitialIntegrate_N: fix nve initial integrate (binning) Kernel execution failed");
	
	#else
		
	int3 layout=getgrid(mynlocal);
	dim3 threads(layout.z, 1, 1);
	dim3 grid(layout.x, layout.y, 1);
    cudaMemset(sdata->buffer,0,sizeof(int));
 	FixNVECuda_InitialIntegrate_Kernel<<<grid, threads>>> (groupbit);
	cudaThreadSynchronize();
	int reneigh_flag;
	cudaMemcpy((void*) (&reneigh_flag), sdata->buffer, sizeof(int),cudaMemcpyDeviceToHost);
	sdata->atom.reneigh_flag+=reneigh_flag;
	CUT_CHECK_ERROR("Cuda_FixNVECuda_InitialIntegrate_N: fix nve initial integrate Kernel execution failed");
	
	#endif
	
}

void Cuda_FixNVECuda_FinalIntegrate(cuda_shared_data* sdata, int groupbit, int mynlocal)//mynlocal can be nfirst if firstgroup==igroup  see cpp
{
	if(sdata->atom.update_nmax) 
		Cuda_FixNVECuda_UpdateNmax(sdata);
	if(sdata->atom.update_nlocal) 		
		cudaMemcpyToSymbol(MY_CONST(nlocal) , & sdata->atom.nlocal , sizeof(int));
	if(sdata->buffer_new)
		Cuda_FixNVECuda_UpdateBuffer(sdata);

	#ifdef CUDA_USE_BINNING
	
	dim3 grid(sdata->domain.bin_dim[0], sdata->domain.bin_dim[1] * sdata->domain.bin_neighbors[2], 1);
	dim3 threads(sdata->domain.bin_nmax, 1, 1);
	FixNVECuda_FinalIntegrate_Kernel<<<grid, threads>>> (groupbit);
	cudaThreadSynchronize();
	CUT_CHECK_ERROR("Cuda_FixNVECuda_FinalIntegrate: fix nve final integrate (binning) Kernel execution failed");
	
	#else
		
	int3 layout=getgrid(mynlocal);
	dim3 threads(layout.z, 1, 1);
	dim3 grid(layout.x, layout.y, 1);
	FixNVECuda_FinalIntegrate_Kernel<<<grid, threads>>> (groupbit);
	cudaThreadSynchronize();
	CUT_CHECK_ERROR("Cuda_FixNVECuda_FinalIntegrate: fix nve final integrate Kernel execution failed");
	
	#endif
}

