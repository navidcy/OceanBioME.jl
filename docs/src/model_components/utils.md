# [Utilities](@id utils)

We provide some utilities that may be useful.

## Time step adaptation
We have added a few additional utilities which extend the capabilities of Oceananigans' time step wizard. For column models where there is no water velocity we have added functions to calculate the advection timescale from the biogeochemical model defined sinking velocities. This could be used by:
```
wizard = TimeStepWizard(cfl = 0.2, diffusive_cfl = 0.2, max_change = 2.0, min_change = 0.5, cell_advection_timescale = column_advection_timescale)
simulation.callbacks[:wizard] = Callback(wizard, IterationInterval(10))
```
Additionally, in a column model you may have a functional definition for the viscosity, so we define an additional diffusion timescale function:
```
wizard = TimeStepWizard(cfl = 0.2, diffusive_cfl = 0.2, max_change = 2.0, min_change = 0.5, cell_diffusion_timescale = column_diffusion_timescale, cell_advection_timescale = column_advection_timescale)
simulation.callbacks[:wizard] = Callback(wizard, IterationInterval(10))
```
Finally, sinking may be more limiting than the normal advective CFL conditions so, we have an additional cell advection timescale defined for 3D models:
```
wizard = TimeStepWizard(cfl = 0.6, diffusive_cfl = 0.5, max_change = 1.5, min_change = 0., cell_advection_timescale = sinking_adveciton_timescale)
simulation.callbacks[:wizard] = Callback(wizard, IterationInterval(10))
```
## Negative tracer detection
As a temporary measure we have implemented a callback to either detect negative tracers and either scale a conserved group, force them back to zero, or throw an error. Please see the numerical implementations' page for details. This can be set up by:
```
negativity_protection! = ScaleNegativeTracers(tracers = (:P, :Z, :N))
simulation.callbacks[:neg] = Callback(negativity_protection!; callsite = UpdateStateCallsite())
```
You may also pass a scale factor for each component (e.g. in case they have different redfield raitos):
```
negativity_protection! = ScaleNegativeTracers(tracers = (:P, :Z, :D), scalefactors = (P = 1, Z = 1, D = 2))
simulation.callbacks[:neg] = Callback(negativity_protection!; callsite = UpdateStateCallsite())
```
Here you should carefully consider which tracers form a conserved group (if at all). Alternatively, force to zero by:
```
simulation.callbacks[:neg] = Callback(OceanBioME.no_negative_tracers!, callsite = UpdateStateCallsite())
```
or throw an error:
```
simulation.callbacks[:neg] = Callback(OceanBioME.error_on_neg!, callsite = UpdateStateCallsite())
```
The latter two both optionally take a named tuple of parameters which may include `exclude` which can be a tuple of tracer names (Symbols) which are allowed to be negative.