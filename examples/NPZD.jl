# # One dimensional column example
# In this example we will setup a simple 1D column with the [LOBSTER](@ref LOBSTER) biogeochemical model and observe its evolution. This demonstrates:
# - How to setup OceanBioME's biogeochemical models
# - How to setup light attenuation
# - How to visualise results

# This is forced by idealised mixing layer depth and surface photosynthetically available radiation (PAR) which are setup first

# ## Install dependencies
# First we will check we have the dependencies installed
# ```julia
# using Pkg
# pkg"add OceanBioME, Oceananigans, Printf, Plots, GLMakie, NetCDF, JLD2"
# ```

# ## Model setup
# We load the packages and choose the default LOBSTER parameter set
using OceanBioME, Oceananigans, Oceananigans.Units, Printf

# ## Surface PAR
PAR⁰(x, y, t) = 50 * (1 - cos((t + 15days) * 2π / (365days))) * (1 / (1 + 0.2 * exp(-((mod(t, 365days)-200days)/50days)^2))) / 2

# ## Grid and PAR field
# Define the grid and an extra Oceananigans field for the PAR to be stored in
grid = RectilinearGrid(size=(20, 30), extent=(200, 300), topology=(Periodic, Flat, Bounded)) 

# ## Model instantiation
Tᵃ(t) = 18 + 2 * sin((t + 15days) * 2π / (365days))
dTdz_0(x, y, t, T) = (Tᵃ(t) - T) * 10 ^ -3 / 1.1 

dTdz = 0.01 # K m⁻¹

T_bcs = FieldBoundaryConditions(top = GradientBoundaryCondition(dTdz_0, field_dependencies = (:T, )),
                                bottom = GradientBoundaryCondition(dTdz))

model = NonhydrostaticModel(; grid,
                              #biogeochemistry = NutrientPhytoplanktonZooplanktonDetritus(; grid, surface_phytosynthetically_active_radiation = PAR⁰),
                              tracers = (:T, :S, ), # T will be defined by the biogeochemistry
                              buoyancy=SeawaterBuoyancy(),
                              boundary_conditions = (T = T_bcs, ),
                              advection = WENO(grid),
                              closure = ScalarDiffusivity(ν=1e-4, κ=1e-4))

## Random noise damped at top and bottom
Ξ(z) = randn() * z / model.grid.Lz * (1 + z / model.grid.Lz) # noise

## Temperature initial condition: a stable density gradient with random noise superposed.
Tᵢ(x, y, z) = 16 + dTdz * z + dTdz * model.grid.Lz * 1e-6 * Ξ(z)

## Velocity initial condition: random noise scaled by the friction velocity.
uᵢ(x, y, z) = 1e-3 * Ξ(z)

## `set!` the `model` fields using functions or constants:
set!(model, u=uᵢ, w=uᵢ, T=Tᵢ, S=35.0)#, N = 2.0, P = 0.1, Z = 0.01)

# ## Simulation
# Next we setup the simulation along with some callbacks that:
# - Update the PAR field from the surface PAR and phytoplankton concentration
# - Show the progress of the simulation
# - Store the output
# - Prevent the tracers from going negative from numerical error (see discussion of this in the [positivity preservation](@ref pos-preservation) implementation page)

simulation = Simulation(model, Δt=0.5minute, stop_time=2years)

# The `TimeStepWizard` helps ensure stable time-stepping
# with a Courant-Freidrichs-Lewy (CFL) number of 1.0.

#simulation.callbacks[:timestep] = Callback(update_timestep!, TimeInterval(1minute), parameters = (w=200/day, c_adv = 0.45, relaxation=0.75, c_forcing=0.1)) 

wizard = TimeStepWizard(cfl = 0.6, diffusive_cfl = 0.5, max_change = 1.5, min_change = 0.5, cell_advection_timescale = sinking_adveciton_timescale)
simulation.callbacks[:wizard] = Callback(wizard, IterationInterval(1))

## Print a progress message
progress(sim) = @printf("Iteration: %d, time: %s, Δt: %s\n",
                        iteration(sim), prettytime(sim), prettytime(sim.Δt))
 
simulation.callbacks[:progress] = Callback(progress, IterationInterval(100))

filename = "npdz"
simulation.output_writers[:profiles] = JLD2OutputWriter(model, merge(model.velocities, model.tracers, model.auxiliary_fields), filename = "$filename.jld2", schedule = TimeInterval(1hour), overwrite_existing=true)

# ## Run!
# Finally we run the simulation
run!(simulation)

# Now we can visualise the results

N = FieldTimeSeries("$filename.jld2", "N")
P = FieldTimeSeries("$filename.jld2", "P")
Z = FieldTimeSeries("$filename.jld2", "Z")
D = FieldTimeSeries("$filename.jld2", "D")
x, y, z = nodes(P)
times = P.times

using GLMakie

n = Observable(1)

N_plt = @lift N[1:20, 1, 1:20, $n]
P_plt = @lift P[1:20, 1, 1:20, $n]
Z_plt = @lift Z[1:20, 1, 1:20, $n]
D_plt = @lift D[1:20, 1, 1:20, $n]

title = @lift @sprintf("t = %s", prettytime(times[$n]))

N_range = (minimum(N), maximum(N))
P_range = (minimum(P), maximum(P))
Z_range = (minimum(Z), maximum(Z))
D_range = (minimum(D), maximum(D))

f=Figure(backgroundcolor=RGBf(1, 1, 1), fontsize=30, resolution=(2400, 2000))

f[1, 1:5] = Label(f, title, textsize=24, tellwidth=false)

axP = Axis(f[2, 1:2], ylabel="z (m)", xlabel="x (m)", title="Phytoplankton concentration (mmol N/m³)")
hmP = heatmap!(axP, x, z, P_plt, interpolate=true, colormap=:batlow, colorrange=P_range)
cbP = Colorbar(f[2, 3], hmP)

axN = Axis(f[2, 4:5], ylabel="z (m)", xlabel="x (m)", title="Nitrate concentration (mmol N/m³)")
hmN = heatmap!(axN, x, z, N_plt, interpolate=true, colormap=:batlow, colorrange=N_range)
cbN = Colorbar(f[2, 6], hmN)

axZ = Axis(f[3, 1:2], ylabel="z (m)", xlabel="x (m)", title="Zooplankton concentration (mmol N/m³)")
hmZ = heatmap!(axZ, x, z, Z_plt, interpolate=true, colormap=:batlow, colorrange=Z_range)
cbZ = Colorbar(f[3, 3], hmZ)

axD = Axis(f[3, 4:5], ylabel="z (m)", xlabel="x (m)", title="Detritus concentration (mmol N/m³)")
hmD = heatmap!(axD, x, z, D_plt, interpolate=true, colormap=:batlow, colorrange=D_range)
cbD = Colorbar(f[3, 6], hmD)

nframes = length(times)
frame_iterator = 1:nframes
framerate = floor(Int, nframes/30)

record(f, "$filename.mp4", frame_iterator; framerate = framerate) do i
    n[] = i
    msg = string("Plotting frame ", i, " of ", nframes)
    print(msg * " \r")
end
