# Make file for non-hydrostatic module source code
# Requires the environment variables FCOMP and NETCDF_ROOT to be set

# This line de-activates all implicit rules
.SUFFIXES: .o .f .F .f90

FFLAGS = -O3

#Debugging options for the compiler
#FFLAGS = -g -check=all -warn=WALL
#FFLAGS = -g -fbacktrace -check=all

# Include paths:
INCS = -I$(NETCDF_ROOT)/include

## Rule to make *.o out of *.f90
.f90.o:
	$(FCOMP) -c $(FFLAGS) -o $*.o $*.f90 $(INCS)

sources = mg_autotune.f90 mg_cst.f90 mg_gather.f90 \
	mg_grids.f90 mg_horiz_grids.f90 mg_intergrids.f90 mg_mpi_exchange.f90\
	mg_mpi.f90 mg_namelist.f90 mg_netcdf_out.f90 mg_projection.f90\
	mg_relax.f90 mg_solvers.f90 mg_tictoc.f90 mg_vert_grids.f90 \
	nhmg_debug.f90 nhmg.f90 mg_netcdf_out_true.f90

objects = $(sources:.f90=.o)

libnhmg =  ../lib/libnhmg.a


.PHONY: all clean depend

all: $(libnhmg)

$(libnhmg): ${libnhmg}(${objects})
	cp *.mod ../include/

depend depend.mk:
	makedepf90 -free ${sources} > depend.mk

clean:
	rm -f ${libnhmg} ${objects} *.mod

include depend.mk
