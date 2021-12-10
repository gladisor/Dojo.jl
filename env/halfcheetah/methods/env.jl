################################################################################
# HalfCheetah
################################################################################
struct HalfCheetah end

function halfcheetah(; mode::Symbol=:min, dt::T=0.05, g::T=-9.81,
    cf::T=0.8, spring=[240, 180, 120, 180, 120, 60.], damper=[6., 4.5, 3., 4.5, 3., 1.5],
    s::Int=1, contact::Bool=true, info=nothing, vis::Visualizer=Visualizer(),
    opts_step=InteriorPointOptions(), opts_grad=InteriorPointOptions()) where T

    mechanism = gethalfcheetah(Δt=dt, g=g, cf=cf, spring=spring, damper=damper)
    initializehalfcheetah!(mechanism)

    if mode == :min
        nx = minCoordDim(mechanism)
    elseif mode == :max
        nx = maxCoordDim(mechanism)
    end
    nu = 6
    no = nx

    aspace = BoxSpace(nu, low=(-1.0e-3 * ones(nu)), high=(1.0e-3 * ones(nu)))
    ospace = BoxSpace(no, low=(-Inf * ones(no)), high=(Inf * ones(no)))

    rng = MersenneTwister(s)

    z = getMaxState(mechanism)
    x = mode == :min ? max2min(mechanism, z) : z

    fx = zeros(nx, nx)
    fu = zeros(nx, nu)

    u_prev = zeros(nu)
    control_mask = [zeros(6, 3) I(nu)]

    build_robot(vis, mechanism)

    TYPES = [HalfCheetah, T, typeof(mechanism), typeof(aspace), typeof(ospace), typeof(info)]
    env = Environment{TYPES...}(mechanism, mode, aspace, ospace,
        x, fx, fu,
        u_prev, control_mask,
        nx, nu, no,
        info,
        [rng], vis,
        opts_step, opts_grad)

    return env
end

function reset(env::Environment{HalfCheetah}; x=nothing, reset_noise_scale = 0.1)
    @show "eee"
    if x != nothing
        env.x .= x
    else
        # initialize above the ground to make sure that with random initialization we do not violate the ground constraint.
        initialize!(env.mechanism, :halfcheetah, z = 0.25)
        x0 = getMinState(env.mechanism)
        nx = minCoordDim(env.mechanism)
        nz = maxCoordDim(env.mechanism)

        low = -reset_noise_scale
        high = reset_noise_scale
        x = x0 + (high - low) .* rand(env.rng[1], nx) .+ low # we ignored the normla distribution on the velocities
        @show "eee"
        @show norm(x - x0)
        @show x0[2]
        @show x[2]
        z = min2max(env.mechanism, x)
        setState!(env.mechanism, z)
        @show getMinState(env.mechanism)[2]
        if env.mode == :min
            env.x .= getMinState(env.mechanism)
        elseif env.mode == :max
            env.x .= getMaxState(env.mechanism)
        end
        env.u_prev .= 0.0
    end
    return _get_obs(env)
end

function cost(env::Environment{HalfCheetah}, x, u;
        forward_reward_weight = 1.0, ctrl_cost_weight = 0.1)

    if env.mode == :min
        x_velocity = -x[5]
    else
        i_torso = findfirst(body -> body.name == "torso", collect(env.mechanism.bodies))
        z_torso = x[(i_torso-1)*13 .+ (1:13)]
        x_velocity = z_torso[4]
    end
    @show u
    c = ctrl_cost_weight * u'*u - x_velocity * forward_reward_weight
    return c
end
