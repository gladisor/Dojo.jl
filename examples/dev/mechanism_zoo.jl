"""
     Mechanism constructor. Provides a simple way to construct a example
     mechanisms: atlas, snake, dice, etc.
"""
function getmechanism(model::Symbol; kwargs...)
    mech = eval(Symbol(:get, model))(; kwargs...)
    return mech
end

function getatlas(; Δt::T = 0.01, g::T = -9.81, cf::T = 0.8, contact::Bool = true) where {T}
    # path = "examples/examples_files/atlas_simple.urdf"
    path = "examples/examples_files/atlas_ones.urdf"
    mech = Mechanism(joinpath(module_dir(), path), floating=true, g = g)
    if contact
        origin = Origin{T}()
        bodies = Vector{Body{T}}(collect(mech.bodies))
        eqs = Vector{EqualityConstraint{T}}(collect(mech.eqconstraints))

        # Foot contact
        contacts = [
            [-0.1; -0.05; 0.0],
            [+0.1; -0.05; 0.0],
            [-0.1; +0.05; 0.0],
            [+0.1; +0.05; 0.0],
            ]
        n = length(contacts)
        normal = [[0;0;1.0] for i = 1:n]
        cf = cf * ones(T, n)

        # conineqcs1, impineqcs1 = splitcontactconstraint(getbody(mech, "l_foot"), normal, cf, p = contacts)
        # conineqcs2, impineqcs2 = splitcontactconstraint(getbody(mech, "r_foot"), normal, cf, p = contacts)
        contineqcs1 = contactconstraint(getbody(mech, "l_foot"), normal, cf, p = contacts)
        contineqcs2 = contactconstraint(getbody(mech, "r_foot"), normal, cf, p = contacts)

        setPosition!(mech, geteqconstraint(mech, "auto_generated_floating_joint"), [0;0;1.2;0.1;0.;0.])
        # mech = Mechanism(origin, bodies, eqs, [impineqcs1; impineqcs2; conineqcs1; conineqcs2], g = g, Δt = Δt)
        mech = Mechanism(origin, bodies, eqs, [contineqcs1; contineqcs2], g = g, Δt = Δt)
    end
    return mech
end

function getdice(; Δt::T = 0.01, g::T = -9.81, cf::T = 0.8, 
        contact::Bool = true,
        conetype = :soc,
        mode=:particle)  where {T}
    # Parameters
    joint_axis = [1.0;0.0;0.0]
    length1 = 0.5
    width, depth = 0.5, 0.5

    origin = Origin{T}()
    link1 = Box(width, depth, length1, 1., color = RGBA(1., 1., 0.))
    joint0to1 = EqualityConstraint(Floating(origin, link1))
    links = [link1]
    eqcs = [joint0to1]

    if contact
        # Corner vectors
        if mode == :particle
            corners = [
                [[0 ; 0; 0.]]
                # [[length1 / 2;length1 / 2;-length1 / 2]]
                # [[length1 / 2;-length1 / 2;-length1 / 2]]
                # [[-length1 / 2;length1 / 2;-length1 / 2]]
                # [[-length1 / 2;-length1 / 2;-length1 / 2]]
                # [[length1 / 2;length1 / 2;length1 / 2]]
                # [[length1 / 2;-length1 / 2;length1 / 2]]
                # [[-length1 / 2;length1 / 2;length1 / 2]]
                # [[-length1 / 2;-length1 / 2;length1 / 2]]
            ]
        elseif mode == :box 
            corners = [
                [[length1 / 2;length1 / 2;-length1 / 2]]
                [[length1 / 2;-length1 / 2;-length1 / 2]]
                [[-length1 / 2;length1 / 2;-length1 / 2]]
                [[-length1 / 2;-length1 / 2;-length1 / 2]]
                [[length1 / 2;length1 / 2;length1 / 2]]
                [[length1 / 2;-length1 / 2;length1 / 2]]
                [[-length1 / 2;length1 / 2;length1 / 2]]
                [[-length1 / 2;-length1 / 2;length1 / 2]]
            ]
        else 
            @error "incorrect mode specified, try :particle or :box" 
        end
        n = length(corners)
        normal = [[0;0;1.0] for i = 1:n]
        cf = cf * ones(n)

        if conetype == :soc
            # conineqcs, impineqcs = splitcontactconstraint(link1, normal, cf, p = corners)
            # mech = Mechanism(origin, links, eqcs, [impineqcs; conineqcs], g = g, Δt = Δt)
            contineqcs = contactconstraint(link1, normal, cf, p = corners)
            mech = Mechanism(origin, links, eqcs, contineqcs, g = g, Δt = Δt)
        elseif conetype == :linear
            fricsandineqs = [Friction(link1, normal[1], cf[1]; p = corners[i]) for i=1:n]
            frics = getindex.(fricsandineqs,1)
            ineqcs = vcat(getindex.(fricsandineqs,2)...)
            mech = Mechanism(origin, links, eqcs, ineqcs, frics, g = g, Δt = Δt)
        else
            error("Unknown conetype")
        end
    else
        mech = Mechanism(origin, links, eqcs, g = g, Δt = Δt)
    end
    return mech
end

function getsnake(; Δt::T = 0.01, g::T = -9.81, cf::T = 0.8, contact::Bool = true,
        conetype = :soc, Nlink::Int = 5) where {T}

    # Parameters
    ex = [1.;0.;0.]
    h = 1.0
    r = 0.05

    vert11 = [0.;0.;h / 2]
    vert12 = -vert11

    # Links
    origin = Origin{T}()
    links = [Cylinder(r, h, h, color = RGBA(1., 0., 0.)) for i = 1:Nlink]

    # Constraints
    jointb1 = EqualityConstraint(Floating(origin, links[1]))
    if Nlink > 1
        eqcs = [
            jointb1;
            [EqualityConstraint(Revolute(links[i - 1], links[i], ex; p1=vert12, p2=vert11)) for i = 2:Nlink]
            ]
    else
        eqcs = [jointb1]
    end

    if contact
        n = Nlink
        normal = [[0;0;1.0] for i = 1:n]
        cf = cf * ones(n)

        if conetype == :soc
            # conineqcs1, impineqcs1 = splitcontactconstraint(links, normal, cf, p = fill(vert11, n))
            # conineqcs2, impineqcs2 = splitcontactconstraint(links, normal, cf, p = fill(vert12, n))
            # mech = Mechanism(origin, links, eqcs, [impineqcs1; impineqcs2; conineqcs1; conineqcs2], g = g, Δt = Δt)
            contineqcs1 = contactconstraint(links, normal, cf, p = fill(vert11, n))
            contineqcs2 = contactconstraint(links, normal, cf, p = fill(vert12, n))
            mech = Mechanism(origin, links, eqcs, [contineqcs1; contineqcs2], g = g, Δt = Δt)

        elseif conetype == :linear
            fricsandineqs1 = [Friction(links[i], normal[i], cf[i]; p = vert11) for i=1:Nlink]
            frics1 = getindex.(fricsandineqs1,1)
            ineqcs1 = vcat(getindex.(fricsandineqs1,2)...)
            fricsandineqs2 = [Friction(links[i], normal[i], cf[i]; p = vert12) for i=1:Nlink]
            frics2 = getindex.(fricsandineqs2,1)
            ineqcs2 = vcat(getindex.(fricsandineqs2,2)...)
            mech = Mechanism(origin, links, eqcs, [ineqcs1;ineqcs2], [frics1;frics2], g = g, Δt = Δt)

        else
            error("Unknown conetype")
        end
    else
        mech = Mechanism(origin, links, eqcs, g = g, Δt = Δt)
    end
    return mech
end

function getpendulum(; Δt::T = 0.01, g::T = -9.81) where {T}
    # Parameters
    joint_axis = [1.0; 0; 0]
    length1 = 1.0
    width, depth = 0.1, 0.1
    p2 = [0; 0; length1/2] # joint connection point

    # Links
    origin = Origin{T}()
    link1 = Box(width, depth, length1, length1)

    # Constraints
    joint_between_origin_and_link1 = EqualityConstraint(Revolute(origin, link1, joint_axis; p2=p2))
    links = [link1]
    eqcs = [joint_between_origin_and_link1]

    mech = Mechanism(origin, links, eqcs, g = g, Δt = Δt)
    return mech
end

function getslider(; Δt::T = 0.01, g::T = -9.81) where {T}
    # Parameters
    joint_axis = [0; 0; 1.0]
    length1 = 1.0
    width, depth = 0.1, 0.1
    p2 = [0; 0; length1/2] # joint connection point

    # Links
    origin = Origin{T}()
    link1 = Box(width, depth, length1, length1)

    # Constraints
    joint_between_origin_and_link1 = EqualityConstraint(Prismatic(origin, link1, joint_axis; p2=p2))
    links = [link1]
    eqcs = [joint_between_origin_and_link1]

    mech = Mechanism(origin, links, eqcs, g = g, Δt = Δt)
    return mech
end

function getnpendulum(; Δt::T = 0.01, g::T = -9.81, Nlink::Int = 5) where {T}
    # Parameters
    ex = [1.; 0; 0]
    h = 1.
    r = .05
    vert11 = [0; 0; h/2]
    vert12 = -vert11

    # Links
    origin = Origin{T}()
    links = [Cylinder(r, h, h, color = RGBA(1., 0., 0.)) for i = 1:Nlink]

    # Constraints
    jointb1 = EqualityConstraint(Revolute(origin, links[1], ex; p2 = vert11))
    if Nlink > 1
        eqcs = [
            jointb1;
            [EqualityConstraint(Revolute(links[i - 1], links[i], ex; p1=vert12, p2=vert11)) for i = 2:Nlink]
            ]
    else
        eqcs = [jointb1]
    end
    mech = Mechanism(origin, links, eqcs, g = g, Δt = Δt)
    return mech
end

function getnslider(; Δt::T = 0.01, g::T = -9.81, Nlink::Int = 5) where {T}
    # Parameters
    ex = [0; 0; 1.0]
    h = 1.
    r = .05
    vert11 = [0; r; 0.0]
    vert12 = -vert11

    # Links
    origin = Origin{T}()
    links = [Cylinder(r, h, h, color = RGBA(1., 0., 0.)) for i = 1:Nlink]

    # Constraints
    # jointb1 = EqualityConstraint(Prismatic(origin, links[1], ex; p2 = vert11))
    # setPosition!(mechanism.origin, link1, p1 = [0, -0.05, 0.0])
    jointb1 = EqualityConstraint(Fixed(origin, links[1]; p1 = 0*vert11, p2 = 0*vert11))
    if Nlink > 1
        eqcs = [
            jointb1;
            [EqualityConstraint(ForcePrismatic(links[i - 1], links[i], ex; p1=vert12, p2=vert11, spring = 1.0, damper = 1.0)) for i = 2:Nlink]
            ]
    else
        eqcs = [jointb1]
    end
    mech = Mechanism(origin, links, eqcs, g = g, Δt = Δt)
    return mech
end

"""
     Mechanism initialization method. Provides a simple way to set the initial
     conditions (pose and velocity) of the mechanism.
"""
function initialize!(mechanism::Mechanism, model::Symbol; kwargs...)
    eval(Symbol(:initialize, model, :!))(mechanism; kwargs...)
end

function initializeatlas!(mechanism::Mechanism; tran::AbstractVector{T} = [0,0,1.2],
        rot::AbstractVector{T} = [0.1,0,0]) where {T}
    setPosition!(mechanism,
                 geteqconstraint(mechanism, "auto_generated_floating_joint"),
                 [tran; rot])
end

function initializedice!(mechanism::Mechanism; x::AbstractVector{T} = [0,0,1.],
        v::AbstractVector{T} = [1,.3,.2], ω::AbstractVector{T} = [2.5,-1,2]) where {T}
    body = collect(mechanism.bodies)[1]
    setPosition!(body, x = x)
    setVelocity!(body, v = v, ω = ω)
end

function initializesnake!(mechanism::Mechanism{T,Nn,Ne,Nb}; x::AbstractVector{T} = [0,-0.5,0],
        v::AbstractVector{T} = [1,.3,4], ω::AbstractVector{T} = [.1,.8,0],
        ϕ1::T = pi/2) where {T,Nn,Ne,Nb}

    link1 = collect(mechanism.bodies)[1]
    h = link1.shape.rh[2]
    vert11 = [0.;0.;h / 2]
    vert12 = -vert11
    # set position and velocities
    setPosition!(mechanism.origin, link1, p2 = x, Δq = UnitQuaternion(RotX(ϕ1)))
    setVelocity!(link1, v = v, ω = ω)

    previd = link1.id
    for body in Iterators.drop(mechanism.bodies, 1)
        setPosition!(getbody(mechanism, previd), body, p1 = vert12, p2 = vert11)
        setVelocity!(body, v = [0.3, 0.4, 0.8], ω = [0.05, 0.02, 0.01])
        previd = body.id
    end
end

function initializenpendulum!(mechanism::Mechanism; ϕ1::T = pi/4) where {T}

    link1 = collect(mechanism.bodies)[1]
    eqc = collect(mechanism.eqconstraints)[1]
    vert11 = eqc.constraints[1].vertices[2]
    vert12 = - vert11

    # set position and velocities
    setPosition!(mechanism.origin, link1, p2 = vert11, Δq = UnitQuaternion(RotX(ϕ1)))

    previd = link1.id
    for body in Iterators.drop(mechanism.bodies, 1)
        setPosition!(getbody(mechanism, previd), body, p1 = vert12, p2 = vert11)
        previd = body.id
    end
end

function initializependulum!(mechanism::Mechanism; ϕ1::T = 0.7) where {T}
    body = collect(mechanism.bodies)[1]
    eqc = collect(mechanism.eqconstraints)[1]
    p2 = eqc.constraints[1].vertices[2]
    q1 = UnitQuaternion(RotX(ϕ1))
    setPosition!(mechanism.origin, body, p2 = p2, Δq = q1)
end

function initializeslider!(mechanism::Mechanism; ϕ1::T = 0.7) where {T}
    body = collect(mechanism.bodies)[1]
    eqc = collect(mechanism.eqconstraints)[1]
    p2 = eqc.constraints[1].vertices[2]
    q1 = UnitQuaternion(RotX(ϕ1))
    setPosition!(mechanism.origin, body, p2 = p2, Δq = q1)
end

function initializenslider!(mechanism::Mechanism; z1::T = 0.2, Δz = 0.0) where {T}
    link1 = collect(mechanism.bodies)[1]
    # set position and velocities
    setPosition!(mechanism.origin, link1, p1 = 0*[0, -0.05, z1])

    previd = link1.id
    for (i,body) in enumerate(Iterators.drop(mechanism.bodies, 1))
        setPosition!(getbody(mechanism, previd), body, p1 = [0, -0.1i, Δz])
        previd = body.id
    end
end
