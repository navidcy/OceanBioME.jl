# # One dimensional column forced by external data with carbonate chemistry
# In this example we will setup a simple 1D column with the [LOBSTER](@ref LOBSTER) biogeochemical model and observe its evolution. This demonstrates:
# - How to setup OceanBioME's biogeochemical models
# - How to load external forcing data
# - How to run with optional tracer sets such as carbonate chemistry
# - How to setup a non-uniform grid for better near surface resolution
# - How to visualise results

# This is forced by mixing layer depth and surface photosynthetically available radiation (PAR) data from the Mercator Ocean model and NASA VIIRS observations

# ## Install dependencies
# First we will check we have the dependencies installed
# ```julia
# using Pkg
# pkg"add OceanBioME, Oceananigans, Printf, Plots, GLMakie, NetCDF, JLD2, DataDeps, Interpolations"
# ```

# ## Model setup
# First load the required packages
using Oceananigans, Random, Printf, NetCDF, Interpolations, DataDeps
using Oceananigans.Units: second, minute, minutes, hour, hours, day, days, year, years
using Oceananigans.Operators: ∂zᶜᶜᶜ
using OceanBioME 

# ## Load external forcing data
# Loading the forcing data from our online copy
dd = DataDep(
    "example_data",
    "example data from subpolar re analysis and observational products", 
    "https://github.com/OceanBioME/OceanBioME_example_data/raw/main/subpolar.nc"
)
register(dd)
filename = datadep"example_data/subpolar.nc"
times = ncread(filename, "time")
temp = ncread(filename, "temp")
salinity = ncread(filename, "so")
mld = ncread(filename, "mld")
par = ncread(filename, "par")

temperature_itp = LinearInterpolation(times, temp) 
salinity_itp = LinearInterpolation(times, salinity) 
mld_itp = LinearInterpolation(times, mld) 
PAR_itp = LinearInterpolation(times, par)

t_function(x, y, z, t) = temperature_itp(mod(t, 364days))
s_function(x, y, z, t) = salinity_itp(mod(t, 364days))
surface_PAR(x, y, t) = PAR_itp(mod(t, 364days))
κₜ(x, y, z, t) = 2e-2*max(1-(z+mld_itp(mod(t,364days))/2)^2/(mld_itp(mod(t,364days))/2)^2,0)+1e-4

# ## Grid and PAR field
# Define the grid (in this case a non uniform grid for better resolution near the surface) and an extra Oceananigans field for the PAR to be stored in
Nz = 33
Lz = 600
refinement = 10 
stretching = 5.754
h(k) = (k - 1) / Nz
ζ₀(k) = 1 + (h(k) - 1) / refinement
Σ(k) = (1 - exp(-stretching * h(k))) / (1 - exp(-stretching))
z_faces(k) = Lz * (ζ₀(k) * Σ(k) - 1)

grid = RectilinearGrid(size = (1, 1, Nz), x = (0, 20), y = (0, 20), z = z_faces)        

# ## Biogeochemical and Oceananigans model
# Here we instantiate the LOBSTER model with carbonate chemistry and a surface flux of DIC (CO₂)
CO₂_flux = GasExchange(; gas = :CO₂, temperature = t_function, salinity = s_function)
model = NonhydrostaticModel(; grid,
                              closure = ScalarDiffusivity(ν=κₜ, κ=κₜ), 
                              biogeochemistry = LOBSTER(; grid,
                                                          surface_phytosynthetically_active_radiation = surface_PAR,
                                                          carbonates = true),
                              boundary_conditions = (DIC = FieldBoundaryConditions(top = CO₂_flux), ),
                              advection = nothing,)

set!(model, P = 0.03, Z = 0.03, NO₃ = 11.0, NH₄ = 0.05, DIC = 2200.0, Alk = 2400.0)

# ## Simulation
# Next we setup the simulation along with some callbacks that:
# - Show the progress of the simulation
# - Store the output
# - Prevent the tracers from going negative from numerical error (see discussion of this in the [positivity preservation](@ref pos-preservation) implimentation page)
# - Adapt the timestep length to reduce the run time

simulation = Simulation(model, Δt=1minutes, stop_time=100days) 

progress_message(sim) = @printf("Iteration: %04d, time: %s, Δt: %s, wall time: %s\n",
                                iteration(sim),
                                prettytime(sim),
                                prettytime(sim.Δt),
                                prettytime(sim.run_wall_time))

simulation.callbacks[:progress] = Callback(progress_message, IterationInterval(100))

filename = "data_forced"
simulation.output_writers[:profiles] = JLD2OutputWriter(model, 
                                                        merge(model.tracers, model.auxiliary_fields), 
                                                        filename = "$filename.jld2", 
                                                        schedule = TimeInterval(1day), 
                                                        overwrite_existing = true)

# TODO: make tendency callback to force no NaNs in tendencies

scale_negative_tracers = ScaleNegativeTracers(; model, tracers = (:NO₃, :NH₄, :P, :Z, :sPOM, :bPOM, :DOM))
simulation.callbacks[:neg] = Callback(scale_negative_tracers; callsite = UpdateStateCallsite())

wizard = TimeStepWizard(cfl = 0.2, diffusive_cfl = 0.2, max_change = 2.0, min_change = 0.5, cell_diffusion_timescale = column_diffusion_timescale, cell_advection_timescale = column_advection_timescale)
simulation.callbacks[:wizard] = Callback(wizard, IterationInterval(10))

# ## Run!
# Finally we run the simulation
run!(simulation)

# Now we can visualise the results with some post processing to diagnose the air-sea CO₂ flux

P = FieldTimeSeries("$filename.jld2", "P")
NO₃ = FieldTimeSeries("$filename.jld2", "NO₃")
Z = FieldTimeSeries("$filename.jld2", "Z")
sPOM = FieldTimeSeries("$filename.jld2", "sPOM") 
bPOM = FieldTimeSeries("$filename.jld2", "bPOM")
DIC = FieldTimeSeries("$filename.jld2", "DIC")
Alk = FieldTimeSeries("$filename.jld2", "Alk")

x, y, z = nodes(P)
times = P.times

air_sea_CO₂_flux = zeros(size(P)[4])
carbon_export = zeros(size(P)[4])
for (i, t) in enumerate(times)
    air_sea_CO₂_flux[i] = CO₂_flux.condition.parameters(0.0, 0.0, t, DIC[1, 1, end, i], Alk[1, 1, end, i], t_function(1, 1, 0, t), s_function(1, 1, 0, t)) 
    carbon_export[i] = model.biogeochemistry.organic_redfield * (sPOM[1, 1, end - 20, i] * model.biogeochemistry.sinking_velocities.sPOM.w[1, 1, end - 20] .+ bPOM[1, 1, end - 20, i] * model.biogeochemistry.sinking_velocities.bPOM.w[1, 1, end - 20])
end

using CairoMakie
f=Figure(backgroundcolor=RGBf(1, 1, 1), fontsize=30, resolution = (1920, 1600))

axP = Axis(f[1, 1:2], ylabel="z (m)", xlabel="Time (days)", title="Phytoplankton concentration (mmol N/m³)")
hmP = heatmap!(times./days, float.(z[end-23:end]), float.(P[1, 1, end-23:end, 1:end])', colormap=:batlow)
cbP = Colorbar(f[1, 3], hmP)

axNO₃ = Axis(f[1, 4:5], ylabel="z (m)", xlabel="Time (days)", title="Nitrate concentration (mmol N/m³)")
hmNO₃ = heatmap!(times./days, float.(z[end-23:end]), float.(NO₃[1, 1, end-23:end, 1:end])', colormap=:batlow)
cbNO₃ = Colorbar(f[1, 6], hmNO₃)

axZ = Axis(f[2, 1:2], ylabel="z (m)", xlabel="Time (days)", title="Zooplankton concentration (mmol N/m³)")
hmZ = heatmap!(times./days, float.(z[end-23:end]), float.(Z[1, 1, end-23:end, 1:end])', colormap=:batlow)
cbZ = Colorbar(f[2, 3], hmZ)

axD = Axis(f[2, 4:5], ylabel="z (m)", xlabel="Time (days)", title="Detritus concentration (mmol N/m³)")
hmD = heatmap!(times./days, float.(z[end-23:end]), float.(sPOM[1, 1, end-23:end, 1:end])' .+ float.(bPOM[1, 1, end-23:end, 1:end])', colormap=:batlow)
cbD = Colorbar(f[2, 6], hmD)

axfDIC = Axis(f[3, 1:6], xlabel="Time (days)", title="Air-sea CO₂ flux and Sinking", ylabel="Flux (kgCO₂/m²/year)")
hmfDIC = lines!(times ./ days, cumsum(air_sea_CO₂_flux) .* (12 + 16 * 2) .* year / (1000 * 1000), label="Air-sea flux")
hmfExp = lines!(times ./ days, cumsum(carbon_export) .* (12 + 16 * 2) .* year / (1000 * 1000), label="Sinking export")

f[3, 5] = Legend(f, axfDIC, "", framevisible = false)

save("data_forced.png", f)

# ![Results](data_forced.png)
