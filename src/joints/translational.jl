mutable struct Translational{T,N} <: Joint{T,N}
    V3::Adjoint{T,SVector{3,T}} # in body1's frame
    V12::SMatrix{2,3,T,6} # in body1's frame
    vertices::NTuple{2,SVector{3,T}} # in body1's & body2's frames

    spring::T
    damper::T

    Fτ::SVector{3,T}

    function Translational{T,N}(body1::AbstractBody, body2::AbstractBody;
            p1::AbstractVector = szeros(T,3), p2::AbstractVector = szeros(T,3), axis::AbstractVector = szeros(T,3), spring = zero(T), damper = zero(T)
        ) where {T,N}

        vertices = (p1, p2)
        V1, V2, V3 = orthogonalrows(axis)
        V12 = [V1;V2]

        Fτ = zeros(T,3)

        new{T,N}(V3, V12, vertices, spring, damper, Fτ), body1.id, body2.id
    end
end

Translational0 = Translational{T,0} where T
Translational1 = Translational{T,1} where T
Translational2 = Translational{T,2} where T
Translational3 = Translational{T,3} where T

springforcea(joint::Translational{T,3}, body1::Body, body2::Body, Δt::T, childid) where T = szeros(T, 6)
springforceb(joint::Translational{T,3}, body1::Body, body2::Body, Δt::T, childid) where T = szeros(T, 6)
springforceb(joint::Translational{T,3}, body1::Origin, body2::Body, Δt::T, childid) where T = szeros(T, 6)

damperforcea(joint::Translational{T,3}, body1::Body, body2::Body, Δt::T, childid) where T = szeros(T, 6)
damperforceb(joint::Translational{T,3}, body1::Body, body2::Body, Δt::T, childid) where T = szeros(T, 6)
damperforceb(joint::Translational{T,3}, body1::Origin, body2::Body, Δt::T, childid) where T = szeros(T, 6)


function Base.show(io::IO, mime::MIME{Symbol("text/plain")}, constraint::Translational{T,N}) where {T,N}
    summary(io, constraint)
    println(io,"")
    println(io, " V3:       "*string(constraint.V3))
    println(io, " V12:      "*string(constraint.V12))
    println(io, " vertices: "*string(constraint.vertices))
end

### Constraints and derivatives
## Position level constraints (for dynamics)
@inline function g(joint::Translational, xa::AbstractVector, qa::UnitQuaternion, xb::AbstractVector, qb::UnitQuaternion)
    vertices = joint.vertices
    return vrotate(xb + vrotate(vertices[2], qb) - (xa + vrotate(vertices[1], qa)), inv(qa))
end
@inline function g(joint::Translational, xb::AbstractVector, qb::UnitQuaternion)
    vertices = joint.vertices
    return xb + vrotate(vertices[2], qb) - vertices[1]
end

## Derivatives NOT accounting for quaternion specialness
@inline function ∂g∂posa(joint::Translational, xa::AbstractVector, qa::UnitQuaternion, xb::AbstractVector, qb::UnitQuaternion)
    point2 = xb + vrotate(joint.vertices[2], qb)

    X = -VLᵀmat(qa) * RVᵀmat(qa)
    Q = 2 * VLᵀmat(qa) * (Lmat(UnitQuaternion(point2)) - Lmat(UnitQuaternion(xa)))

    return X, Q
end
@inline function ∂g∂posb(joint::Translational, xa::AbstractVector, qa::UnitQuaternion, xb::AbstractVector, qb::UnitQuaternion)
    X = VLᵀmat(qa) * RVᵀmat(qa)
    Q = 2 * VLᵀmat(qa) * Rmat(qa) * Rᵀmat(qb) * Rmat(UnitQuaternion(joint.vertices[2]))

    return X, Q
end
@inline function ∂g∂posb(joint::Translational, xb::AbstractVector, qb::UnitQuaternion)
    X = I
    Q = 2 * VRᵀmat(qb) * Rmat(UnitQuaternion(joint.vertices[2]))

    return X, Q
end

## vec(G) Jacobian (also NOT accounting for quaternion specialness in the second derivative: ∂(∂ʳg∂posx)∂y)
@inline function ∂2g∂posaa(joint::Translational{T}, xa::AbstractVector, qa::UnitQuaternion, xb::AbstractVector, qb::UnitQuaternion) where T
    Lpos = Lmat(UnitQuaternion(xb + vrotate(joint.vertices[2], qb) - xa))
    Ltpos = Lᵀmat(UnitQuaternion(xb + vrotate(joint.vertices[2], qb) - xa))

    XX = szeros(T, 9, 3)
    XQ = -kron(Vmat(T),VLᵀmat(qa))*∂R∂qsplit(T) - kron(VRᵀmat(qa),Vmat(T))*∂Lᵀ∂qsplit(T)
    QX = -kron(VLᵀmat(qa),2*VLᵀmat(qa))*∂L∂qsplit(T)[:,SA[2; 3; 4]]
    QQ = kron(Vmat(T),2*VLᵀmat(qa)*Lpos)*∂L∂qsplit(T) + kron(VLᵀmat(qa)*Ltpos,2*Vmat(T))*∂Lᵀ∂qsplit(T)

    return XX, XQ, QX, QQ
end
@inline function ∂2g∂posab(joint::Translational{T}, xa::AbstractVector, qa::UnitQuaternion, xb::AbstractVector, qb::UnitQuaternion) where T
    XX = szeros(T, 9, 3)
    XQ = szeros(T, 9, 4)
    QX = kron(VLᵀmat(qa),2*VLᵀmat(qa))*∂L∂qsplit(T)[:,SA[2; 3; 4]]
    QQ = kron(VLᵀmat(qa),2*VLᵀmat(qa)*Lmat(qb)*Lmat(UnitQuaternion(joint.vertices[2])))*∂Lᵀ∂qsplit(T) + kron(VLᵀmat(qa)*Lmat(qb)*Lᵀmat(UnitQuaternion(joint.vertices[2])),2*VLᵀmat(qa))*∂L∂qsplit(T)

    return XX, XQ, QX, QQ
end
@inline function ∂2g∂posba(joint::Translational{T}, xa::AbstractVector, qa::UnitQuaternion, xb::AbstractVector, qb::UnitQuaternion) where T
    XX = szeros(T, 9, 3)
    XQ = kron(Vmat(T),VLᵀmat(qa))*∂R∂qsplit(T) + kron(VRᵀmat(qa),Vmat(T))*∂Lᵀ∂qsplit(T)
    QX = szeros(T, 9, 3)
    QQ = kron(VLᵀmat(qb)*Rᵀmat(UnitQuaternion(joint.vertices[2]))*Rmat(qb),2*VLᵀmat(qa))*∂R∂qsplit(T) + kron(VLᵀmat(qb)*Rᵀmat(UnitQuaternion(joint.vertices[2]))*Rmat(qb)*Rᵀmat(qa),2*Vmat(T))*∂Lᵀ∂qsplit(T)

    return XX, XQ, QX, QQ
end
@inline function ∂2g∂posbb(joint::Translational{T}, xa::AbstractVector, qa::UnitQuaternion, xb::AbstractVector, qb::UnitQuaternion) where T
    XX = szeros(T, 9, 3)
    XQ = szeros(T, 9, 4)
    QX = szeros(T, 9, 3)
    QQ = kron(Vmat(T),2*VLᵀmat(qa)*Rmat(qa)*Rᵀmat(qb)*Rmat(UnitQuaternion(joint.vertices[2])))*∂L∂qsplit(T) + kron(VLᵀmat(qb)*Rᵀmat(UnitQuaternion(joint.vertices[2])),2*VLᵀmat(qa)*Rmat(qa))*∂Rᵀ∂qsplit(T)

    return XX, XQ, QX, QQ
end
@inline function ∂2g∂posbb(joint::Translational{T}, xb::AbstractVector, qb::UnitQuaternion) where T
    XX = szeros(T, 9, 3)
    XQ = szeros(T, 9, 4)
    QX = szeros(T, 9, 3)
    QQ = kron(Vmat(T),2*VRᵀmat(qb)*Rmat(UnitQuaternion(joint.vertices[2])))*∂L∂qsplit(T) + kron(VLᵀmat(qb)*Rᵀmat(UnitQuaternion(joint.vertices[2])),2*Vmat(T))*∂Rᵀ∂qsplit(T)

    return XX, XQ, QX, QQ
end


# ### Spring and damper
# ## Forces for dynamics
# # Force applied by body b on body a expressed in world frame
# @inline function springforcea(joint::Translational, xa::AbstractVector, qa::UnitQuaternion, xb::AbstractVector, qb::UnitQuaternion)
#     A = nullspacemat(joint)
#     Aᵀ = zerodimstaticadjoint(A)
#     distance = A * g(joint, xa, qa, xb, qb)
#     force = Aᵀ * A * joint.spring * Aᵀ * distance  # Currently assumes same spring constant in all directions
#     return [force;szeros(3)]
# end
# # Force applied by body a on body b expressed in world frame
# @inline function springforceb(joint::Translational, xa::AbstractVector, qa::UnitQuaternion, xb::AbstractVector, qb::UnitQuaternion)
#     A = nullspacemat(joint)
#     Aᵀ = zerodimstaticadjoint(A)
#     distance = A * g(joint, xa, qa, xb, qb)
#     force = - Aᵀ * A * joint.spring * Aᵀ * distance  # Currently assumes same spring constant in all directions
#     return [force;szeros(3)]
# end
# # Force applied by origin on body b expressed in world frame
# @inline function springforceb(joint::Translational, xb::AbstractVector, qb::UnitQuaternion)
#     A = nullspacemat(joint)
#     Aᵀ = zerodimstaticadjoint(A)
#     distance = A * g(joint, xb, qb)
#     force = - Aᵀ * A * joint.spring * Aᵀ * distance  # Currently assumes same spring constant in all directions
#     return [force;szeros(3)]
# end
#
# # Force applied by body b on body a expressed in world frame
# @inline function damperforcea(joint::Translational, va::AbstractVector, vb::AbstractVector)
#     A = nullspacemat(joint)
#     Aᵀ = zerodimstaticadjoint(A)
#     velocity = A * (vb - va)
#     force = Aᵀ * A * joint.damper * Aᵀ * velocity  # Currently assumes same damper constant in all directions
#     return [force;szeros(3)]
# end
# # Force applied by body a on body b expressed in world frame
# @inline function damperforceb(joint::Translational, va::AbstractVector, vb::AbstractVector)
#     A = nullspacemat(joint)
#     Aᵀ = zerodimstaticadjoint(A)
#     velocity = A * (vb - va)
#     force = - Aᵀ * A * joint.damper * Aᵀ * velocity  # Currently assumes same damper constant in all directions
#     return [force;szeros(3)]
# end
# # Force applied by origin on body b expressed in world frame
# @inline function damperforceb(joint::Translational, vb::AbstractVector)
#     A = nullspacemat(joint)
#     Aᵀ = zerodimstaticadjoint(A)
#     velocity = A * vb
#     force = - Aᵀ * A * joint.damper * Aᵀ * velocity  # Currently assumes same damper constant in all directions
#     return [force;szeros(3)]
# end

# ### Spring and damper
# ## Forces for dynamics
# # Force applied by body a on body b expressed in world frame
# @inline function springforce(joint::Force12, xa::AbstractVector, qa::UnitQuaternion,
#         xb::AbstractVector, qb::UnitQuaternion)
#     A = constraintmat(joint)
#     Aᵀ = zerodimstaticadjoint(A)
#     distance = A * gc(joint, xa, qa, xb, qb)
#     force = - Aᵀ * A * joint.spring * Aᵀ * distance  # Currently assumes same spring constant in all directions
#     return force
# end
# # Force applied by origin on body b expressed in world frame
# @inline function springforce(joint::Force12, xb::AbstractVector, qb::UnitQuaternion)
#     A = constraintmat(joint)
#     Aᵀ = zerodimstaticadjoint(A)
#     distance = A * gc(joint, xb, qb)
#     force = - Aᵀ * A * joint.spring * Aᵀ * distance  # Currently assumes same spring constant in all directions
#     return force
# end
# # Force applied by body a on body b expressed in world frame
# @inline function damperforce(joint::Force12, va::AbstractVector, vb::AbstractVector)
#     A = constraintmat(joint)
#     Aᵀ = zerodimstaticadjoint(A)
#     velocity = A * (vb - va)
#     force = - Aᵀ * A * joint.damper * Aᵀ * velocity  # Currently assumes same damper constant in all directions
#     return force
# end
# # Force applied by origin on body b expressed in world frame
# @inline function damperforce(joint::Force12, vb::AbstractVector)
#     A = constraintmat(joint)
#     Aᵀ = zerodimstaticadjoint(A)
#     velocity = A * vb
#     force = - Aᵀ * A * joint.damper * Aᵀ * velocity  # Currently assumes same damper constant in all directions
#     return force
# end


#
# ## Damper velocity derivatives
# @inline function diagonal∂damper∂ʳvel(joint::Translational{T}) where T
#     A = nullspacemat(joint)
#     AᵀA = zerodimstaticadjoint(A) * A
#     Z = szeros(T, 3, 3)
#     return [[-AᵀA * joint.damper * AᵀA; Z] [Z; Z]]
# end
# @inline function offdiagonal∂damper∂ʳvel(joint::Translational{T}, xa::AbstractVector, qa::UnitQuaternion, xb::AbstractVector, qb::UnitQuaternion) where T
#     A = nullspacemat(joint)
#     AᵀA = zerodimstaticadjoint(A) * A
#     Z = szeros(T, 3, 3)
#     return [[AᵀA * joint.damper * AᵀA; Z] [Z; Z]]
# end
# @inline function offdiagonal∂damper∂ʳvel(joint::Translational{T}, xb::AbstractVector, qb::UnitQuaternion) where T
#     A = nullspacemat(joint)
#     AᵀA = zerodimstaticadjoint(A) * A
#     Z = szeros(T, 3, 3)
#     return [[AᵀA * joint.damper * AᵀA; Z] [Z; Z]]
# end

### Forcing
## Application of joint forces (for dynamics)
@inline function applyFτ!(joint::Translational{T}, statea::State, stateb::State, Δt::T, clear::Bool) where T
    F = joint.Fτ
    vertices = joint.vertices
    _, qa = posargsnext(statea, Δt)
    _, qb = posargsnext(stateb, Δt)

    Fa = vrotate(-F, qa)
    Fb = -Fa

    τa = vrotate(torqueFromForce(Fa, vrotate(vertices[1], qa)),inv(qa)) # in local coordinates
    τb = vrotate(torqueFromForce(Fb, vrotate(vertices[2], qb)),inv(qb)) # in local coordinates

    statea.Fk[end] += Fa
    statea.τk[end] += τa
    stateb.Fk[end] += Fb
    stateb.τk[end] += τb
    clear && (joint.Fτ = szeros(T,3))
    return
end
@inline function applyFτ!(joint::Translational{T}, stateb::State, Δt::T, clear::Bool) where T
    F = joint.Fτ
    vertices = joint.vertices
    _, qb = posargsnext(stateb, Δt)

    Fb = F
    τb = vrotate(torqueFromForce(Fb, vrotate(vertices[2], qb)),inv(qb)) # in local coordinates

    stateb.Fk[end] += Fb
    stateb.τk[end] += τb
    clear && (joint.Fτ = szeros(T,3))
    return
end

## Forcing derivatives (for linearization)
# Control derivatives
@inline function ∂Fτ∂ua(joint::Translational, statea::State, stateb::State, Δt::T) where T
    vertices = joint.vertices
    _, qa = posargsnext(statea, Δt)

    BFa = -VLmat(qa) * RᵀVᵀmat(qa)
    Bτa = -skew(vertices[1])

    return [BFa; Bτa]
end
@inline function ∂Fτ∂ub(joint::Translational, statea::State, stateb::State, Δt::T) where T
    vertices = joint.vertices
    xa, qa = posargsnext(statea, Δt)
    xb, qb = posargsnext(stateb, Δt)
    qbinvqa = qb\qa

    BFb = VLmat(qa) * RᵀVᵀmat(qa)
    Bτb = skew(vertices[2]) * VLmat(qbinvqa) * RᵀVᵀmat(qbinvqa)

    return [BFb; Bτb]
end
@inline function ∂Fτ∂ub(joint::Translational, stateb::State, Δt::T) where T
    vertices = joint.vertices
    _, qb = posargsnext(stateb, Δt)

    BFb = I
    Bτb = skew(vertices[2]) * VLᵀmat(qb) * RVᵀmat(qb)

    return [BFb; Bτb]
end

# Position derivatives
@inline function ∂Fτ∂posa(joint::Translational{T}, statea::State, stateb::State, Δt::T) where T
    _, qa = posargsnext(statea, Δt)
    _, qb = posargsnext(stateb, Δt)
    F = joint.Fτ
    vertices = joint.vertices

    FaXa = szeros(T,3,3)
    FaQa = -2*VRᵀmat(qa)*Rmat(UnitQuaternion(F))#*LVᵀmat(qa)
    τaXa = szeros(T,3,3)
    τaQa = szeros(T,3,4)
    FbXa = szeros(T,3,3)
    FbQa = 2*VRᵀmat(qa)*Rmat(UnitQuaternion(F))#*LVᵀmat(qa)
    τbXa = szeros(T,3,3)
    τbQa = 2*skew(vertices[2])*VLᵀmat(qb)*Rmat(qb)*Rᵀmat(qa)*Rmat(UnitQuaternion(F))#*LVᵀmat(qa)

    return FaXa, FaQa, τaXa, τaQa, FbXa, FbQa, τbXa, τbQa
end
@inline function ∂Fτ∂posb(joint::Translational{T}, statea::State, stateb::State, Δt::T) where T
    _, qa = posargsnext(statea, Δt)
    _, qb = posargsnext(stateb, Δt)
    F = joint.Fτ
    vertices = joint.vertices

    FaXb = szeros(T,3,3)
    FaQb = szeros(T,3,4)
    τaXb = szeros(T,3,3)
    τaQb = szeros(T,3,4)
    FbXb = szeros(T,3,3)
    FbQb = szeros(T,3,4)
    τbXb = szeros(T,3,3)
    τbQb = 2*skew(vertices[2])*VLᵀmat(qb)*Lmat(qa)*Lmat(UnitQuaternion(F))*Lᵀmat(qa)#*LVᵀmat(qb)

    return FaXb, FaQb, τaXb, τaQb, FbXb, FbQb, τbXb, τbQb
end
@inline function ∂Fτ∂posb(joint::Translational{T}, stateb::State, Δt::T) where T
    xb, qb = posargsnext(stateb, Δt)
    F = joint.Fτ
    vertices = joint.vertices

    FaXb = szeros(T,3,3)
    FaQb = szeros(T,3,4)
    τaXb = szeros(T,3,3)
    τaQb = szeros(T,3,4)
    FbXb = szeros(T,3,3)
    FbQb = szeros(T,3,4)
    τbXb = szeros(T,3,3)
    τbQb = 2*skew(vertices[2])*VLᵀmat(qb)*Lmat(UnitQuaternion(F))#*LVᵀmat(qb)

    return FaXb, FaQb, τaXb, τaQb, FbXb, FbQb, τbXb, τbQb
end


### Minimal coordinates
## Position and velocity offsets
@inline function getPositionDelta(joint::Translational, body1::AbstractBody, body2::Body, x::SVector)
    Δx = zerodimstaticadjoint(nullspacemat(joint)) * x # in body1 frame
    return Δx
end
@inline function getVelocityDelta(joint::Translational, body1::AbstractBody, body2::Body, v::SVector)
    Δv = zerodimstaticadjoint(nullspacemat(joint)) * v # in body1 frame
    return Δv
end

## Minimal coordinate calculation
@inline function minimalCoordinates(joint::Translational, body1::Body, body2::Body)
    statea = body1.state
    stateb = body2.state
    return nullspacemat(joint) * g(joint, statea.xc, statea.qc, stateb.xc, stateb.qc)
end
@inline function minimalCoordinates(joint::Translational, body1::Origin, body2::Body)
    stateb = body2.state
    return nullspacemat(joint) * g(joint, stateb.xc, stateb.qc)
end
@inline function minimalVelocities(joint::Translational, body1::Body, body2::Body)
    statea = body1.state
    stateb = body2.state
    return nullspacemat(joint) * (stateb.vc - statea.vc)
end
@inline function minimalVelocities(joint::Translational, body1::Origin, body2::Body)
    stateb = body2.state
    return nullspacemat(joint) * stateb.vc
end


function _dGaa(joint::Translational{T,N}, xa::AbstractVector, qa::UnitQuaternion, xb::AbstractVector, qb::UnitQuaternion, λ::AbstractVector) where {T,N}
    xa₁, xa₂, xa₃ = xa
    qa₁, qa₂, qa₃, qa₄ = [qa.w, qa.x, qa.y, qa.z]
    xb₁, xb₂, xb₃ = xb
    qb₁, qb₂, qb₃, qb₄ = [qb.w, qb.x, qb.y, qb.z]
    v₁, v₂, v₃ = joint.vertices[2]
    λ₁, λ₂, λ₃ = λ

    dG = zeros(6, 7)

    dG[1, 1] = 0
    dG[1, 2] = 0
    dG[1, 3] = 0
    dG[1, 4] = 2qa₄*λ₂ - (2qa₁*λ₁) - (2qa₃*λ₃)
    dG[1, 5] = -2qa₂*λ₁ - (2qa₃*λ₂) - (2qa₄*λ₃)
    dG[1, 6] = 2qa₃*λ₁ - (2qa₁*λ₃) - (2qa₂*λ₂)
    dG[1, 7] = 2qa₁*λ₂ + 2qa₄*λ₁ - (2qa₂*λ₃)
    dG[2, 1] = 0
    dG[2, 2] = 0
    dG[2, 3] = 0
    dG[2, 4] = 2qa₂*λ₃ - (2qa₁*λ₂) - (2qa₄*λ₁)
    dG[2, 5] = 2qa₁*λ₃ + 2qa₂*λ₂ - (2qa₃*λ₁)
    dG[2, 6] = -2qa₂*λ₁ - (2qa₃*λ₂) - (2qa₄*λ₃)
    dG[2, 7] = 2qa₄*λ₂ - (2qa₁*λ₁) - (2qa₃*λ₃)
    dG[3, 1] = 0
    dG[3, 2] = 0
    dG[3, 3] = 0
    dG[3, 4] = 2qa₃*λ₁ - (2qa₁*λ₃) - (2qa₂*λ₂)
    dG[3, 5] = 2qa₂*λ₃ - (2qa₁*λ₂) - (2qa₄*λ₁)
    dG[3, 6] = 2qa₁*λ₁ + 2qa₃*λ₃ - (2qa₄*λ₂)
    dG[3, 7] = -2qa₂*λ₁ - (2qa₃*λ₂) - (2qa₄*λ₃)

    dG[4, 1] = λ₂*(-4qa₁*qa₃ - (4qa₂*qa₄)) + λ₃*(4qa₂*qa₃ - (4qa₁*qa₄))
    dG[4, 2] = λ₂*(4qa₁*qa₂ - (4qa₃*qa₄)) + λ₃*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2)))
    dG[4, 3] = λ₂*(2(qa₂^2) + 2(qa₃^2) - (2(qa₁^2)) - (2(qa₄^2))) + λ₃*(4qa₁*qa₂ + 4qa₃*qa₄)
    dG[4, 4] = λ₁*(qa₄*(2xa₃ + 2qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + 2qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - (2xb₃) - (2qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (2qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)))) + 2qa₄*(xb₃ + qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - xa₃ - (qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))) - (2qa₂*(xa₁ + qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) + qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - xb₁ - (qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))))) - (qa₂*(2xb₁ + 2qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + 2qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - (2xa₁) - (2qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (2qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))))) - (2qa₃*(xa₂ + qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - xb₂ - (qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))) - (qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))))) - (qa₃*(2xb₂ + 2qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + 2qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - (2xa₂) - (2qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (2qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))))) + λ₂*(qa₁*(2xb₃ + 2qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + 2qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - (2xa₃) - (2qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (2qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))) + 2qa₁*(xb₃ + qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - xa₃ - (qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))) + 2qa₂*(xa₂ + qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - xb₂ - (qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))) - (qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)))) - (qa₂*(2xb₂ + 2qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + 2qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - (2xa₂) - (2qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (2qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))))) - (2qa₃*(xa₁ + qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) + qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - xb₁ - (qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))))) - (qa₃*(2xa₁ + 2qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) + 2qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - (2xb₁) - (2qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (2qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)))))) + λ₃*(qa₁*(2xa₂ + 2qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + 2qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - (2xb₂) - (2qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))) - (2qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)))) + qa₄*(2xb₁ + 2qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + 2qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - (2xa₁) - (2qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (2qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)))) + 2qa₁*(xa₂ + qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - xb₂ - (qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))) - (qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)))) - (2qa₂*(xb₃ + qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - xa₃ - (qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))))) - (qa₂*(2xb₃ + 2qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + 2qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - (2xa₃) - (2qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (2qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))))) - (2qa₄*(xa₁ + qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) + qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - xb₁ - (qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))))))
    dG[4, 5] = λ₁*(qa₁*(2xb₁ + 2qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + 2qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - (2xa₁) - (2qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (2qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)))) + qa₄*(2xb₂ + 2qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + 2qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - (2xa₂) - (2qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (2qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))) + 2qa₃*(xb₃ + qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - xa₃ - (qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))) - (2qa₁*(xb₁ + qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - xa₁ - (qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))))) - (qa₃*(2xb₃ + 2qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + 2qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - (2xa₃) - (2qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (2qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))))) - (2qa₄*(xb₂ + qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - xa₂ - (qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))))) + λ₂*(qa₁*(2xa₂ + 2qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + 2qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - (2xb₂) - (2qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))) - (2qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)))) + qa₄*(2xb₁ + 2qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + 2qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - (2xa₁) - (2qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (2qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)))) + 2qa₄*(xb₁ + qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - xa₁ - (qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)))) - (2qa₁*(xb₂ + qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - xa₂ - (qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))))) - (2qa₂*(xb₃ + qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - xa₃ - (qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))))) - (qa₂*(2xb₃ + 2qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + 2qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - (2xa₃) - (2qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (2qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))))) + λ₃*(qa₁*(2xa₃ + 2qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + 2qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - (2xb₃) - (2qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (2qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)))) + 2qa₂*(xb₂ + qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - xa₂ - (qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))) - (2qa₁*(xb₃ + qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - xa₃ - (qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))))) - (qa₂*(2xa₂ + 2qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + 2qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - (2xb₂) - (2qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))) - (2qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))))) - (2qa₃*(xb₁ + qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - xa₁ - (qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))))) - (qa₃*(2xb₁ + 2qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + 2qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - (2xa₁) - (2qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (2qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))))))
    dG[4, 6] = λ₁*(qa₁*(2xb₂ + 2qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + 2qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - (2xa₂) - (2qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (2qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))) + qa₄*(2xa₁ + 2qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) + 2qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - (2xb₁) - (2qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (2qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)))) + 2qa₂*(xa₃ + qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - xb₃ - (qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)))) - (2qa₁*(xb₂ + qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - xa₂ - (qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))))) - (qa₂*(2xa₃ + 2qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + 2qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - (2xb₃) - (2qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (2qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))))) - (2qa₄*(xa₁ + qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) + qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - xb₁ - (qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)))))) + λ₂*(qa₁*(2xb₁ + 2qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + 2qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - (2xa₁) - (2qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (2qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)))) + qa₄*(2xb₂ + 2qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + 2qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - (2xa₂) - (2qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (2qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))) + 2qa₃*(xa₃ + qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - xb₃ - (qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)))) + 2qa₄*(xb₂ + qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - xa₂ - (qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))) - (2qa₁*(xa₁ + qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) + qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - xb₁ - (qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))))) - (qa₃*(2xb₃ + 2qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + 2qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - (2xa₃) - (2qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (2qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))))) + λ₃*(qa₄*(2xa₃ + 2qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + 2qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - (2xb₃) - (2qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (2qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)))) + 2qa₂*(xa₁ + qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) + qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - xb₁ - (qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)))) + 2qa₄*(xa₃ + qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - xb₃ - (qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)))) - (qa₂*(2xb₁ + 2qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + 2qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - (2xa₁) - (2qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (2qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))))) - (2qa₃*(xb₂ + qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - xa₂ - (qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))))) - (qa₃*(2xb₂ + 2qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + 2qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - (2xa₂) - (2qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (2qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))))))
    dG[4, 7] = λ₁*(qa₁*(2xb₃ + 2qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + 2qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - (2xa₃) - (2qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (2qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))) + 2qa₁*(xa₃ + qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - xb₃ - (qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)))) - (2qa₂*(xa₂ + qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - xb₂ - (qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))) - (qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))))) - (qa₂*(2xb₂ + 2qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + 2qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - (2xa₂) - (2qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (2qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))))) - (2qa₃*(xb₁ + qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - xa₁ - (qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))))) - (qa₃*(2xa₁ + 2qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) + 2qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - (2xb₁) - (2qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (2qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)))))) + λ₂*(qa₄*(2xb₃ + 2qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + 2qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - (2xa₃) - (2qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (2qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))) + 2qa₂*(xb₁ + qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - xa₁ - (qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)))) - (qa₂*(2xa₁ + 2qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) + 2qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - (2xb₁) - (2qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (2qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))))) - (2qa₃*(xa₂ + qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - xb₂ - (qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))) - (qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))))) - (qa₃*(2xa₂ + 2qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + 2qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - (2xb₂) - (2qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))) - (2qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))))) - (2qa₄*(xa₃ + qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - xb₃ - (qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)))))) + λ₃*(qa₁*(2xb₁ + 2qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + 2qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - (2xa₁) - (2qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (2qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)))) + qa₄*(2xb₂ + 2qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + 2qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - (2xa₂) - (2qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (2qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))) + 2qa₁*(xb₁ + qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - xa₁ - (qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)))) + 2qa₃*(xa₃ + qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - xb₃ - (qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)))) - (qa₃*(2xb₃ + 2qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + 2qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - (2xa₃) - (2qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (2qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))))) - (2qa₄*(xa₂ + qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - xb₂ - (qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))) - (qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))))))

    dG[5, 1] = λ₁*(4qa₁*qa₃ + 4qa₂*qa₄) + λ₃*(2(qa₃^2) + 2(qa₄^2) - (2(qa₁^2)) - (2(qa₂^2)))
    dG[5, 2] = λ₁*(4qa₃*qa₄ - (4qa₁*qa₂)) + λ₃*(-4qa₁*qa₄ - (4qa₂*qa₃))
    dG[5, 3] = λ₁*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))) + λ₃*(4qa₁*qa₃ - (4qa₂*qa₄))
    dG[5, 4] = λ₁*(qa₁*(2xa₃ + 2qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + 2qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - (2xb₃) - (2qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (2qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)))) + qa₂*(2xb₂ + 2qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + 2qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - (2xa₂) - (2qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (2qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))) + 2qa₁*(xa₃ + qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - xb₃ - (qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)))) - (2qa₂*(xa₂ + qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - xb₂ - (qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))) - (qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))))) - (2qa₃*(xb₁ + qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - xa₁ - (qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))))) - (qa₃*(2xb₁ + 2qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + 2qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - (2xa₁) - (2qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (2qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)))))) + λ₂*(qa₂*(2xa₁ + 2qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) + 2qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - (2xb₁) - (2qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (2qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)))) + 2qa₂*(xb₁ + qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - xa₁ - (qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)))) - (2qa₃*(xa₂ + qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - xb₂ - (qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))) - (qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))))) - (qa₃*(2xb₂ + 2qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + 2qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - (2xa₂) - (2qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (2qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))))) - (2qa₄*(xa₃ + qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - xb₃ - (qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))))) - (qa₄*(2xb₃ + 2qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + 2qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - (2xa₃) - (2qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (2qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))))) + λ₃*(qa₁*(2xb₁ + 2qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + 2qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - (2xa₁) - (2qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (2qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)))) + 2qa₁*(xb₁ + qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - xa₁ - (qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)))) + 2qa₃*(xa₃ + qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - xb₃ - (qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)))) - (qa₃*(2xb₃ + 2qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + 2qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - (2xa₃) - (2qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (2qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))))) - (2qa₄*(xa₂ + qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - xb₂ - (qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))) - (qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))))) - (qa₄*(2xa₂ + 2qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + 2qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - (2xb₂) - (2qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))) - (2qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))))))
    dG[5, 5] = λ₁*(qa₁*(2xb₂ + 2qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + 2qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - (2xa₂) - (2qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (2qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))) + qa₂*(2xb₃ + 2qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + 2qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - (2xa₃) - (2qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (2qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))) + 2qa₁*(xb₂ + qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - xa₂ - (qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))) + 2qa₄*(xa₁ + qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) + qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - xb₁ - (qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)))) - (2qa₂*(xa₃ + qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - xb₃ - (qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))))) - (qa₄*(2xb₁ + 2qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + 2qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - (2xa₁) - (2qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (2qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)))))) + λ₂*(qa₁*(2xb₁ + 2qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + 2qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - (2xa₁) - (2qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (2qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)))) + 2qa₁*(xa₁ + qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) + qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - xb₁ - (qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)))) - (2qa₃*(xa₃ + qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - xb₃ - (qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))))) - (qa₃*(2xb₃ + 2qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + 2qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - (2xa₃) - (2qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (2qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))))) - (2qa₄*(xb₂ + qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - xa₂ - (qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))))) - (qa₄*(2xa₂ + 2qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + 2qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - (2xb₂) - (2qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))) - (2qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)))))) + λ₃*(qa₂*(2xb₁ + 2qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + 2qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - (2xa₁) - (2qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (2qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)))) + 2qa₃*(xb₂ + qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - xa₂ - (qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))) - (2qa₂*(xa₁ + qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) + qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - xb₁ - (qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))))) - (qa₃*(2xa₂ + 2qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + 2qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - (2xb₂) - (2qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))) - (2qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))))) - (2qa₄*(xa₃ + qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - xb₃ - (qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))))) - (qa₄*(2xa₃ + 2qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + 2qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - (2xb₃) - (2qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (2qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))))))
    dG[5, 6] = λ₁*(qa₁*(2xa₁ + 2qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) + 2qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - (2xb₁) - (2qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (2qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)))) + 2qa₃*(xb₃ + qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - xa₃ - (qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))) - (2qa₁*(xb₁ + qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - xa₁ - (qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))))) - (qa₃*(2xa₃ + 2qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + 2qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - (2xb₃) - (2qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (2qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))))) - (2qa₄*(xb₂ + qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - xa₂ - (qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))))) - (qa₄*(2xb₂ + 2qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + 2qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - (2xa₂) - (2qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (2qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))))) + λ₂*(qa₁*(2xb₂ + 2qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + 2qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - (2xa₂) - (2qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (2qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))) + qa₂*(2xb₃ + 2qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + 2qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - (2xa₃) - (2qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (2qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))) + 2qa₄*(xb₁ + qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - xa₁ - (qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)))) - (2qa₁*(xb₂ + qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - xa₂ - (qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))))) - (2qa₂*(xb₃ + qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - xa₃ - (qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))))) - (qa₄*(2xb₁ + 2qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + 2qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - (2xa₁) - (2qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (2qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)))))) + λ₃*(qa₁*(2xa₃ + 2qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + 2qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - (2xb₃) - (2qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (2qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)))) + qa₂*(2xb₂ + 2qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + 2qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - (2xa₂) - (2qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (2qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))) + 2qa₂*(xb₂ + qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - xa₂ - (qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))) - (2qa₁*(xb₃ + qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - xa₃ - (qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))))) - (2qa₃*(xb₁ + qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - xa₁ - (qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))))) - (qa₃*(2xb₁ + 2qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + 2qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - (2xa₁) - (2qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (2qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))))))
    dG[5, 7] = λ₁*(qa₂*(2xa₁ + 2qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) + 2qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - (2xb₁) - (2qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (2qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)))) + 2qa₂*(xa₁ + qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) + qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - xb₁ - (qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)))) + 2qa₃*(xa₂ + qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - xb₂ - (qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))) - (qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)))) - (qa₃*(2xb₂ + 2qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + 2qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - (2xa₂) - (2qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (2qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))))) - (2qa₄*(xb₃ + qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - xa₃ - (qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))))) - (qa₄*(2xb₃ + 2qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + 2qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - (2xa₃) - (2qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (2qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))))) + λ₂*(qa₁*(2xb₃ + 2qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + 2qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - (2xa₃) - (2qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (2qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))) + qa₂*(2xa₂ + 2qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + 2qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - (2xb₂) - (2qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))) - (2qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)))) + 2qa₃*(xa₁ + qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) + qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - xb₁ - (qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)))) - (2qa₁*(xb₃ + qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - xa₃ - (qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))))) - (2qa₂*(xa₂ + qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - xb₂ - (qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))) - (qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))))) - (qa₃*(2xa₁ + 2qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) + 2qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - (2xb₁) - (2qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (2qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)))))) + λ₃*(qa₁*(2xb₂ + 2qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + 2qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - (2xa₂) - (2qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (2qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))) + qa₂*(2xb₃ + 2qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + 2qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - (2xa₃) - (2qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (2qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))) + 2qa₂*(xb₃ + qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - xa₃ - (qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))) + 2qa₄*(xa₁ + qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) + qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - xb₁ - (qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)))) - (2qa₁*(xa₂ + qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - xb₂ - (qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))) - (qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))))) - (qa₄*(2xb₁ + 2qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + 2qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - (2xa₁) - (2qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (2qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))))))

    dG[6, 1] = λ₁*(4qa₁*qa₄ - (4qa₂*qa₃)) + λ₂*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2)))
    dG[6, 2] = λ₁*(2(qa₂^2) + 2(qa₄^2) - (2(qa₁^2)) - (2(qa₃^2))) + λ₂*(4qa₁*qa₄ + 4qa₂*qa₃)
    dG[6, 3] = λ₁*(-4qa₁*qa₂ - (4qa₃*qa₄)) + λ₂*(4qa₂*qa₄ - (4qa₁*qa₃))
    dG[6, 4] = λ₁*(qa₁*(2xb₂ + 2qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + 2qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - (2xa₂) - (2qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (2qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))) + 2qa₁*(xb₂ + qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - xa₂ - (qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))) + 2qa₄*(xa₁ + qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) + qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - xb₁ - (qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)))) - (2qa₂*(xa₃ + qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - xb₃ - (qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))))) - (qa₂*(2xa₃ + 2qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + 2qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - (2xb₃) - (2qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (2qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))))) - (qa₄*(2xb₁ + 2qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + 2qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - (2xa₁) - (2qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (2qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)))))) + λ₂*(qa₁*(2xa₁ + 2qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) + 2qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - (2xb₁) - (2qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (2qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)))) + qa₃*(2xb₃ + 2qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + 2qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - (2xa₃) - (2qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (2qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))) + 2qa₁*(xa₁ + qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) + qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - xb₁ - (qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)))) - (2qa₃*(xa₃ + qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - xb₃ - (qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))))) - (2qa₄*(xb₂ + qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - xa₂ - (qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))))) - (qa₄*(2xb₂ + 2qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + 2qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - (2xa₂) - (2qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (2qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))))) + λ₃*(qa₃*(2xa₂ + 2qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + 2qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - (2xb₂) - (2qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))) - (2qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)))) + 2qa₃*(xb₂ + qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - xa₂ - (qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))) - (2qa₂*(xa₁ + qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) + qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - xb₁ - (qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))))) - (qa₂*(2xb₁ + 2qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + 2qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - (2xa₁) - (2qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (2qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))))) - (2qa₄*(xa₃ + qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - xb₃ - (qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))))) - (qa₄*(2xb₃ + 2qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + 2qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - (2xa₃) - (2qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (2qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))))))
    dG[6, 5] = λ₁*(qa₁*(2xb₃ + 2qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + 2qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - (2xa₃) - (2qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (2qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))) + qa₃*(2xb₁ + 2qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + 2qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - (2xa₁) - (2qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (2qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)))) + 2qa₂*(xa₂ + qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - xb₂ - (qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))) - (qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)))) + 2qa₃*(xb₁ + qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - xa₁ - (qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)))) - (2qa₁*(xa₃ + qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - xb₃ - (qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))))) - (qa₂*(2xb₂ + 2qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + 2qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - (2xa₂) - (2qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (2qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))))) + λ₂*(qa₃*(2xa₂ + 2qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + 2qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - (2xb₂) - (2qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))) - (2qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)))) + 2qa₃*(xa₂ + qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - xb₂ - (qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))) - (qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)))) + 2qa₄*(xa₃ + qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - xb₃ - (qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)))) - (2qa₂*(xb₁ + qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - xa₁ - (qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))))) - (qa₂*(2xb₁ + 2qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + 2qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - (2xa₁) - (2qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (2qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))))) - (qa₄*(2xb₃ + 2qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + 2qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - (2xa₃) - (2qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (2qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))))) + λ₃*(qa₁*(2xb₁ + 2qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + 2qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - (2xa₁) - (2qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (2qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)))) + qa₃*(2xa₃ + 2qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + 2qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - (2xb₃) - (2qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (2qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)))) + 2qa₄*(xa₂ + qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - xb₂ - (qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))) - (qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)))) - (2qa₁*(xb₁ + qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - xa₁ - (qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))))) - (2qa₃*(xa₃ + qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - xb₃ - (qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))))) - (qa₄*(2xa₂ + 2qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + 2qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - (2xb₂) - (2qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))) - (2qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))))))
    dG[6, 6] = λ₁*(qa₃*(2xb₂ + 2qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + 2qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - (2xa₂) - (2qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (2qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))) + 2qa₄*(xb₃ + qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - xa₃ - (qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))) - (2qa₂*(xa₁ + qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) + qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - xb₁ - (qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))))) - (qa₂*(2xa₁ + 2qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) + 2qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - (2xb₁) - (2qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (2qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))))) - (2qa₃*(xa₂ + qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - xb₂ - (qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))) - (qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))))) - (qa₄*(2xa₃ + 2qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + 2qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - (2xb₃) - (2qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (2qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)))))) + λ₂*(qa₁*(2xb₃ + 2qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + 2qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - (2xa₃) - (2qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (2qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))) + qa₃*(2xb₁ + 2qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + 2qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - (2xa₁) - (2qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (2qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)))) + 2qa₁*(xb₃ + qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - xa₃ - (qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))) + 2qa₂*(xa₂ + qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - xb₂ - (qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))) - (qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)))) - (qa₂*(2xb₂ + 2qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + 2qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - (2xa₂) - (2qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (2qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))))) - (2qa₃*(xa₁ + qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) + qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - xb₁ - (qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)))))) + λ₃*(qa₁*(2xb₂ + 2qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + 2qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - (2xa₂) - (2qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (2qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))) + 2qa₁*(xa₂ + qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - xb₂ - (qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))) - (qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)))) - (2qa₂*(xb₃ + qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - xa₃ - (qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))))) - (qa₂*(2xa₃ + 2qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + 2qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - (2xb₃) - (2qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (2qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))))) - (2qa₄*(xa₁ + qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) + qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - xb₁ - (qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))))) - (qa₄*(2xb₁ + 2qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + 2qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - (2xa₁) - (2qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (2qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))))))
    dG[6, 7] = λ₁*(qa₁*(2xa₁ + 2qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) + 2qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - (2xb₁) - (2qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (2qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)))) + qa₃*(2xb₃ + 2qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + 2qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - (2xa₃) - (2qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (2qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))) + 2qa₃*(xb₃ + qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - xa₃ - (qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))) - (2qa₁*(xb₁ + qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - xa₁ - (qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))))) - (2qa₄*(xb₂ + qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - xa₂ - (qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))))) - (qa₄*(2xb₂ + 2qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + 2qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - (2xa₂) - (2qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (2qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))))) + λ₂*(qa₁*(2xa₂ + 2qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + 2qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) - (2xb₂) - (2qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))) - (2qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)))) + 2qa₄*(xb₁ + qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - xa₁ - (qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)))) - (2qa₁*(xb₂ + qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - xa₂ - (qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))))) - (2qa₂*(xb₃ + qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - xa₃ - (qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))))) - (qa₂*(2xb₃ + 2qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + 2qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - (2xa₃) - (2qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (2qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))))) - (qa₄*(2xa₁ + 2qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)) + 2qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - (2xb₁) - (2qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (2qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)))))) + λ₃*(qa₁*(2xb₃ + 2qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + 2qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - (2xa₃) - (2qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (2qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))) + qa₃*(2xb₁ + 2qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + 2qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - (2xa₁) - (2qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (2qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)))) + 2qa₂*(xb₂ + qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - xa₂ - (qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃)))) - (2qa₁*(xb₃ + qb₁*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) + qb₂*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) - xa₃ - (qb₃*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂))) - (qb₄*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))))) - (qa₂*(2xb₂ + 2qb₁*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃)) + 2qb₄*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) - (2xa₂) - (2qb₂*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁))) - (2qb₃*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))))) - (2qa₃*(xb₁ + qb₁*(qb₁*v₁ + qb₃*v₃ - (qb₄*v₂)) + qb₃*(qb₁*v₃ + qb₂*v₂ - (qb₃*v₁)) - xa₁ - (qb₂*(-qb₂*v₁ - (qb₃*v₂) - (qb₄*v₃))) - (qb₄*(qb₁*v₂ + qb₄*v₁ - (qb₂*v₃))))))

    return dG
end

function _dGab(joint::Translational{T,N}, xa::AbstractVector, qa::UnitQuaternion, xb::AbstractVector, qb::UnitQuaternion, λ::AbstractVector) where {T,N}
    xa₁, xa₂, xa₃ = xa
    qa₁, qa₂, qa₃, qa₄ = [qa.w, qa.x, qa.y, qa.z]
    xb₁, xb₂, xb₃ = xb
    qb₁, qb₂, qb₃, qb₄ = [qb.w, qb.x, qb.y, qb.z]
    v₁, v₂, v₃ = joint.vertices[2]
    λ₁, λ₂, λ₃ = λ

    dG = zeros(6, 7)

    dG[1, 1] = 0
    dG[1, 2] = 0
    dG[1, 3] = 0
    dG[1, 4] = 0
    dG[1, 5] = 0
    dG[1, 6] = 0
    dG[1, 7] = 0
    dG[2, 1] = 0
    dG[2, 2] = 0
    dG[2, 3] = 0
    dG[2, 4] = 0
    dG[2, 5] = 0
    dG[2, 6] = 0
    dG[2, 7] = 0
    dG[3, 1] = 0
    dG[3, 2] = 0
    dG[3, 3] = 0
    dG[3, 4] = 0
    dG[3, 5] = 0
    dG[3, 6] = 0
    dG[3, 7] = 0
    dG[4, 1] = λ₂*(4qa₁*qa₃ + 4qa₂*qa₄) + λ₃*(4qa₁*qa₄ - (4qa₂*qa₃))
    dG[4, 2] = λ₂*(4qa₃*qa₄ - (4qa₁*qa₂)) + λ₃*(2(qa₂^2) + 2(qa₄^2) - (2(qa₁^2)) - (2(qa₃^2)))
    dG[4, 3] = λ₂*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))) + λ₃*(-4qa₁*qa₂ - (4qa₃*qa₄))
    dG[4, 4] = λ₁*(qa₁*(2qa₄*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁)) - (2qa₂*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃))) - (2qa₃*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁)))) + qa₄*(2qa₁*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂)) - (2qa₂*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁))) - (2qa₃*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)))) - (qa₂*(2qa₁*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)) + 2qa₄*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃)) - (2qa₃*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁))))) - (qa₃*(2qa₁*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃)) + 2qa₄*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃)) - (2qa₂*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂)))))) + λ₂*(qa₁*(2qa₁*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁)) + 2qa₂*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁)) - (2qa₃*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃)))) + qa₄*(2qa₂*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)) - (2qa₃*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁))) - (2qa₄*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂)))) - (qa₂*(2qa₁*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃)) + 2qa₂*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁)) - (2qa₄*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂))))) - (qa₃*(2qa₁*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃)) - (2qa₃*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂))) - (2qa₄*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃)))))) + λ₃*(qa₁*(2qa₁*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁)) - (2qa₂*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁))) - (2qa₄*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃)))) + qa₄*(2qa₁*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)) + 2qa₃*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂)) - (2qa₄*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁)))) - (qa₂*(2qa₁*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁)) + 2qa₃*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)) - (2qa₂*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃))))) - (qa₃*(2qa₃*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃)) - (2qa₂*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃))) - (2qa₄*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂))))))
    dG[4, 5] = λ₁*(qa₁*(2qa₄*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃)) - (2qa₂*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃))) - (2qa₃*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁)))) + qa₄*(2qa₁*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁)) - (2qa₂*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁))) - (2qa₃*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃))) - (qa₂*(2qa₁*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃) + 2qa₄*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂)) - (2qa₃*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃))))) - (qa₃*(2qa₁*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂)) + 2qa₄*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃)) - (2qa₂*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁)))))) + λ₂*(qa₁*(2qa₁*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃)) + 2qa₂*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁)) - (2qa₃*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃)))) + qa₄*(2qa₂*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃) - (2qa₃*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁))) - (2qa₄*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁)))) - (qa₂*(2qa₁*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂)) + 2qa₂*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃)) - (2qa₄*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃)))) - (qa₃*(2qa₁*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃)) - (2qa₃*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁))) - (2qa₄*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂)))))) + λ₃*(qa₁*(2qa₁*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁)) - (2qa₂*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃))) - (2qa₄*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃)))) + qa₄*(2qa₁*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃) + 2qa₃*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁)) - (2qa₄*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁)))) - (qa₂*(2qa₁*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃)) + 2qa₃*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃) - (2qa₂*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂))))) - (qa₃*(2qa₃*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂)) - (2qa₂*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃))) - (2qa₄*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁))))))
    dG[4, 6] = λ₁*(qa₁*(2qa₄*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃)) - (2qa₂*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂))) - (2qa₃*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃)))) + qa₄*(2qa₁*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)) - (2qa₂*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃))) - (2qa₃*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁)))) - (qa₂*(2qa₁*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁)) + 2qa₄*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃) - (2qa₃*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃))))) - (qa₃*(2qa₁*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃) + 2qa₄*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂)) - (2qa₂*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)))))) + λ₂*(qa₁*(2qa₁*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃)) + 2qa₂*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃)) - (2qa₃*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂)))) + qa₄*(2qa₂*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁)) - (2qa₃*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃))) - (2qa₄*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)))) - (qa₂*(2qa₁*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃) + 2qa₂*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃)) - (2qa₄*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁))))) - (qa₃*(2qa₁*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂)) - (2qa₃*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂))) - (2qa₄*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃))))) + λ₃*(qa₁*(2qa₁*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃)) - (2qa₂*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃))) - (2qa₄*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂)))) + qa₄*(2qa₁*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁)) + 2qa₃*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)) - (2qa₄*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃)))) - (qa₂*(2qa₁*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃)) + 2qa₃*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁)) - (2qa₂*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃)))) - (qa₃*(2qa₃*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃) - (2qa₂*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂))) - (2qa₄*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂))))))
    dG[4, 7] = λ₁*(qa₁*(2qa₄*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃) - (2qa₂*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃))) - (2qa₃*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃)))) + qa₄*(2qa₁*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃)) - (2qa₂*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃))) - (2qa₃*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁)))) - (qa₂*(2qa₁*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁)) + 2qa₄*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)) - (2qa₃*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃)))) - (qa₃*(2qa₁*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)) + 2qa₄*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃)) - (2qa₂*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃)))))) + λ₂*(qa₁*(2qa₁*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃) + 2qa₂*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃)) - (2qa₃*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃)))) + qa₄*(2qa₂*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁)) - (2qa₃*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃))) - (2qa₄*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃)))) - (qa₂*(2qa₁*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)) + 2qa₂*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃) - (2qa₄*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁))))) - (qa₃*(2qa₁*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃)) - (2qa₃*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃))) - (2qa₄*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)))))) + λ₃*(qa₁*(2qa₁*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃)) - (2qa₂*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃)) - (2qa₄*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃)))) + qa₄*(2qa₁*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁)) + 2qa₃*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃)) - (2qa₄*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃)))) - (qa₂*(2qa₁*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃) + 2qa₃*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁)) - (2qa₂*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂))))) - (qa₃*(2qa₃*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)) - (2qa₂*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃))) - (2qa₄*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃))))))
    dG[5, 1] = λ₁*(-4qa₁*qa₃ - (4qa₂*qa₄)) + λ₃*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2)))
    dG[5, 2] = λ₁*(4qa₁*qa₂ - (4qa₃*qa₄)) + λ₃*(4qa₁*qa₄ + 4qa₂*qa₃)
    dG[5, 3] = λ₁*(2(qa₂^2) + 2(qa₃^2) - (2(qa₁^2)) - (2(qa₄^2))) + λ₃*(4qa₂*qa₄ - (4qa₁*qa₃))
    dG[5, 4] = λ₁*(qa₁*(2qa₁*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂)) - (2qa₂*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁))) - (2qa₃*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)))) + qa₂*(2qa₁*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃)) + 2qa₄*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃)) - (2qa₂*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂)))) - (qa₃*(2qa₁*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)) + 2qa₄*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃)) - (2qa₃*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁))))) - (qa₄*(2qa₄*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁)) - (2qa₂*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃))) - (2qa₃*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁)))))) + λ₂*(qa₁*(2qa₂*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)) - (2qa₃*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁))) - (2qa₄*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂)))) + qa₂*(2qa₁*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃)) - (2qa₃*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂))) - (2qa₄*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃)))) - (qa₃*(2qa₁*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃)) + 2qa₂*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁)) - (2qa₄*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂))))) - (qa₄*(2qa₁*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁)) + 2qa₂*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁)) - (2qa₃*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃)))))) + λ₃*(qa₁*(2qa₁*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)) + 2qa₃*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂)) - (2qa₄*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁)))) + qa₂*(2qa₃*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃)) - (2qa₂*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃))) - (2qa₄*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂)))) - (qa₃*(2qa₁*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁)) + 2qa₃*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)) - (2qa₂*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃))))) - (qa₄*(2qa₁*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁)) - (2qa₂*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁))) - (2qa₄*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃))))))
    dG[5, 5] = λ₁*(qa₁*(2qa₁*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁)) - (2qa₂*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁))) - (2qa₃*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃))) + qa₂*(2qa₁*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂)) + 2qa₄*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃)) - (2qa₂*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁)))) - (qa₃*(2qa₁*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃) + 2qa₄*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂)) - (2qa₃*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃))))) - (qa₄*(2qa₄*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃)) - (2qa₂*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃))) - (2qa₃*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁)))))) + λ₂*(qa₁*(2qa₂*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃) - (2qa₃*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁))) - (2qa₄*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁)))) + qa₂*(2qa₁*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃)) - (2qa₃*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁))) - (2qa₄*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂)))) - (qa₃*(2qa₁*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂)) + 2qa₂*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃)) - (2qa₄*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃)))) - (qa₄*(2qa₁*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃)) + 2qa₂*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁)) - (2qa₃*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃)))))) + λ₃*(qa₁*(2qa₁*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃) + 2qa₃*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁)) - (2qa₄*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁)))) + qa₂*(2qa₃*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂)) - (2qa₂*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃))) - (2qa₄*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁)))) - (qa₃*(2qa₁*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃)) + 2qa₃*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃) - (2qa₂*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂))))) - (qa₄*(2qa₁*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁)) - (2qa₂*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃))) - (2qa₄*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃))))))
    dG[5, 6] = λ₁*(qa₁*(2qa₁*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)) - (2qa₂*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃))) - (2qa₃*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁)))) + qa₂*(2qa₁*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃) + 2qa₄*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂)) - (2qa₂*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)))) - (qa₃*(2qa₁*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁)) + 2qa₄*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃) - (2qa₃*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃))))) - (qa₄*(2qa₄*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃)) - (2qa₂*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂))) - (2qa₃*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃)))))) + λ₂*(qa₁*(2qa₂*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁)) - (2qa₃*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃))) - (2qa₄*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)))) + qa₂*(2qa₁*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂)) - (2qa₃*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂))) - (2qa₄*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃))) - (qa₃*(2qa₁*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃) + 2qa₂*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃)) - (2qa₄*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁))))) - (qa₄*(2qa₁*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃)) + 2qa₂*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃)) - (2qa₃*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂)))))) + λ₃*(qa₁*(2qa₁*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁)) + 2qa₃*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)) - (2qa₄*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃)))) + qa₂*(2qa₃*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃) - (2qa₂*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂))) - (2qa₄*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)))) - (qa₃*(2qa₁*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃)) + 2qa₃*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁)) - (2qa₂*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃)))) - (qa₄*(2qa₁*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃)) - (2qa₂*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃))) - (2qa₄*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂))))))
    dG[5, 7] = λ₁*(qa₁*(2qa₁*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃)) - (2qa₂*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃))) - (2qa₃*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁)))) + qa₂*(2qa₁*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)) + 2qa₄*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃)) - (2qa₂*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃)))) - (qa₃*(2qa₁*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁)) + 2qa₄*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)) - (2qa₃*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃)))) - (qa₄*(2qa₄*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃) - (2qa₂*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃))) - (2qa₃*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃)))))) + λ₂*(qa₁*(2qa₂*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁)) - (2qa₃*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃))) - (2qa₄*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃)))) + qa₂*(2qa₁*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃)) - (2qa₃*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃))) - (2qa₄*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)))) - (qa₃*(2qa₁*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)) + 2qa₂*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃) - (2qa₄*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁))))) - (qa₄*(2qa₁*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃) + 2qa₂*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃)) - (2qa₃*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃)))))) + λ₃*(qa₁*(2qa₁*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁)) + 2qa₃*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃)) - (2qa₄*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃)))) + qa₂*(2qa₃*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)) - (2qa₂*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃))) - (2qa₄*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃)))) - (qa₃*(2qa₁*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃) + 2qa₃*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁)) - (2qa₂*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂))))) - (qa₄*(2qa₁*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃)) - (2qa₂*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃)) - (2qa₄*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃))))))
    dG[6, 1] = λ₁*(4qa₂*qa₃ - (4qa₁*qa₄)) + λ₂*(2(qa₃^2) + 2(qa₄^2) - (2(qa₁^2)) - (2(qa₂^2)))
    dG[6, 2] = λ₁*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2))) + λ₂*(-4qa₁*qa₄ - (4qa₂*qa₃))
    dG[6, 3] = λ₁*(4qa₁*qa₂ + 4qa₃*qa₄) + λ₂*(4qa₁*qa₃ - (4qa₂*qa₄))
    dG[6, 4] = λ₁*(qa₁*(2qa₁*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃)) + 2qa₄*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃)) - (2qa₂*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂)))) + qa₃*(2qa₄*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁)) - (2qa₂*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃))) - (2qa₃*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁)))) - (qa₂*(2qa₁*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂)) - (2qa₂*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁))) - (2qa₃*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂))))) - (qa₄*(2qa₁*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)) + 2qa₄*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃)) - (2qa₃*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁)))))) + λ₂*(qa₁*(2qa₁*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃)) - (2qa₃*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂))) - (2qa₄*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃)))) + qa₃*(2qa₁*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁)) + 2qa₂*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁)) - (2qa₃*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃)))) - (qa₂*(2qa₂*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)) - (2qa₃*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁))) - (2qa₄*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂))))) - (qa₄*(2qa₁*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃)) + 2qa₂*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁)) - (2qa₄*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)))))) + λ₃*(qa₁*(2qa₃*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃)) - (2qa₂*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃))) - (2qa₄*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂)))) + qa₃*(2qa₁*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁)) - (2qa₂*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁))) - (2qa₄*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃)))) - (qa₂*(2qa₁*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)) + 2qa₃*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂)) - (2qa₄*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁))))) - (qa₄*(2qa₁*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁)) + 2qa₃*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)) - (2qa₂*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃))))))
    dG[6, 5] = λ₁*(qa₁*(2qa₁*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂)) + 2qa₄*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃)) - (2qa₂*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁)))) + qa₃*(2qa₄*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃)) - (2qa₂*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃))) - (2qa₃*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁)))) - (qa₂*(2qa₁*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁)) - (2qa₂*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁))) - (2qa₃*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃)))) - (qa₄*(2qa₁*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃) + 2qa₄*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂)) - (2qa₃*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃)))))) + λ₂*(qa₁*(2qa₁*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃)) - (2qa₃*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁))) - (2qa₄*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂)))) + qa₃*(2qa₁*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃)) + 2qa₂*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁)) - (2qa₃*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃)))) - (qa₂*(2qa₂*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃) - (2qa₃*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁))) - (2qa₄*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁))))) - (qa₄*(2qa₁*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂)) + 2qa₂*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃)) - (2qa₄*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃))))) + λ₃*(qa₁*(2qa₃*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂)) - (2qa₂*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃))) - (2qa₄*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁)))) + qa₃*(2qa₁*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁)) - (2qa₂*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃))) - (2qa₄*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃)))) - (qa₂*(2qa₁*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃) + 2qa₃*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁)) - (2qa₄*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁))))) - (qa₄*(2qa₁*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃)) + 2qa₃*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃) - (2qa₂*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂))))))
    dG[6, 6] = λ₁*(qa₁*(2qa₁*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃) + 2qa₄*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂)) - (2qa₂*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)))) + qa₃*(2qa₄*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃)) - (2qa₂*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂))) - (2qa₃*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃)))) - (qa₂*(2qa₁*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)) - (2qa₂*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃))) - (2qa₃*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁))))) - (qa₄*(2qa₁*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁)) + 2qa₄*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃) - (2qa₃*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃)))))) + λ₂*(qa₁*(2qa₁*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂)) - (2qa₃*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂))) - (2qa₄*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃))) + qa₃*(2qa₁*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃)) + 2qa₂*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃)) - (2qa₃*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂)))) - (qa₂*(2qa₂*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁)) - (2qa₃*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃))) - (2qa₄*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂))))) - (qa₄*(2qa₁*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃) + 2qa₂*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃)) - (2qa₄*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁)))))) + λ₃*(qa₁*(2qa₃*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃) - (2qa₂*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂))) - (2qa₄*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)))) + qa₃*(2qa₁*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃)) - (2qa₂*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃))) - (2qa₄*(2qb₃*v₁ - (2qb₁*v₃) - (2qb₂*v₂)))) - (qa₂*(2qa₁*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁)) + 2qa₃*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)) - (2qa₄*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃))))) - (qa₄*(2qa₁*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃)) + 2qa₃*(2qb₁*v₃ + 2qb₂*v₂ - (2qb₃*v₁)) - (2qa₂*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃)))))
    dG[6, 7] = λ₁*(qa₁*(2qa₁*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)) + 2qa₄*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃)) - (2qa₂*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃)))) + qa₃*(2qa₄*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃) - (2qa₂*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃))) - (2qa₃*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃)))) - (qa₂*(2qa₁*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃)) - (2qa₂*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃))) - (2qa₃*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁))))) - (qa₄*(2qa₁*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁)) + 2qa₄*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)) - (2qa₃*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃))))) + λ₂*(qa₁*(2qa₁*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃)) - (2qa₃*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃))) - (2qa₄*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)))) + qa₃*(2qa₁*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃) + 2qa₂*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃)) - (2qa₃*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃)))) - (qa₂*(2qa₂*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁)) - (2qa₃*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃))) - (2qa₄*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃))))) - (qa₄*(2qa₁*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)) + 2qa₂*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃) - (2qa₄*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁)))))) + λ₃*(qa₁*(2qa₃*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂)) - (2qa₂*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃))) - (2qa₄*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃)))) + qa₃*(2qa₁*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃)) - (2qa₂*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃)) - (2qa₄*(2qb₁*v₂ + 2qb₄*v₁ - (2qb₂*v₃)))) - (qa₂*(2qa₁*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁)) + 2qa₃*(-2qb₂*v₁ - (2qb₃*v₂) - (2qb₄*v₃)) - (2qa₄*(2qb₄*v₂ - (2qb₁*v₁) - (2qb₃*v₃))))) - (qa₄*(2qa₁*(2qb₂*v₁ + 2qb₃*v₂ + 2qb₄*v₃) + 2qa₃*(2qb₂*v₃ - (2qb₁*v₂) - (2qb₄*v₁)) - (2qa₂*(2qb₁*v₁ + 2qb₃*v₃ - (2qb₄*v₂))))))

    return dG
end

function _dGba(joint::Translational{T,N}, xa::AbstractVector, qa::UnitQuaternion, xb::AbstractVector, qb::UnitQuaternion, λ::AbstractVector) where {T,N}
    xa₁, xa₂, xa₃ = xa
    qa₁, qa₂, qa₃, qa₄ = [qa.w, qa.x, qa.y, qa.z]
    xb₁, xb₂, xb₃ = xb
    qb₁, qb₂, qb₃, qb₄ = [qb.w, qb.x, qb.y, qb.z]
    v₁, v₂, v₃ = joint.vertices[2]
    λ₁, λ₂, λ₃ = λ

    dG = zeros(6, 7)

    dG[1, 1] = 0
    dG[1, 2] = 0
    dG[1, 3] = 0
    dG[1, 4] = 2qa₁*λ₁ + 2qa₃*λ₃ - (2qa₄*λ₂)
    dG[1, 5] = 2qa₂*λ₁ + 2qa₃*λ₂ + 2qa₄*λ₃
    dG[1, 6] = 2qa₁*λ₃ + 2qa₂*λ₂ - (2qa₃*λ₁)
    dG[1, 7] = 2qa₂*λ₃ - (2qa₁*λ₂) - (2qa₄*λ₁)
    dG[2, 1] = 0
    dG[2, 2] = 0
    dG[2, 3] = 0
    dG[2, 4] = 2qa₁*λ₂ + 2qa₄*λ₁ - (2qa₂*λ₃)
    dG[2, 5] = 2qa₃*λ₁ - (2qa₁*λ₃) - (2qa₂*λ₂)
    dG[2, 6] = 2qa₂*λ₁ + 2qa₃*λ₂ + 2qa₄*λ₃
    dG[2, 7] = 2qa₁*λ₁ + 2qa₃*λ₃ - (2qa₄*λ₂)
    dG[3, 1] = 0
    dG[3, 2] = 0
    dG[3, 3] = 0
    dG[3, 4] = 2qa₁*λ₃ + 2qa₂*λ₂ - (2qa₃*λ₁)
    dG[3, 5] = 2qa₁*λ₂ + 2qa₄*λ₁ - (2qa₂*λ₃)
    dG[3, 6] = 2qa₄*λ₂ - (2qa₁*λ₁) - (2qa₃*λ₃)
    dG[3, 7] = 2qa₂*λ₁ + 2qa₃*λ₂ + 2qa₄*λ₃
    dG[4, 1] = 0
    dG[4, 2] = 0
    dG[4, 3] = 0
    dG[4, 4] = λ₁*(qb₁*(v₂*(4qa₁*qb₃ - (4qa₃*qb₁) - (4qa₄*qb₂)) - (v₁*(4qa₃*qb₄ - (4qa₁*qb₂) - (4qa₄*qb₃))) - (v₃*(4qa₄*qb₁ - (4qa₁*qb₄) - (4qa₃*qb₂)))) + qb₄*(v₃*(4qa₁*qb₁ + 4qa₃*qb₃ + 4qa₄*qb₄) - (v₁*(4qa₁*qb₃ - (4qa₃*qb₁) - (4qa₄*qb₂))) - (v₂*(4qa₃*qb₄ - (4qa₁*qb₂) - (4qa₄*qb₃)))) - (qb₂*(v₁*(4qa₁*qb₁ + 4qa₃*qb₃ + 4qa₄*qb₄) + v₂*(4qa₄*qb₁ - (4qa₁*qb₄) - (4qa₃*qb₂)) + v₃*(4qa₁*qb₃ - (4qa₃*qb₁) - (4qa₄*qb₂)))) - (qb₃*(v₁*(4qa₄*qb₁ - (4qa₁*qb₄) - (4qa₃*qb₂)) - (v₂*(4qa₁*qb₁ + 4qa₃*qb₃ + 4qa₄*qb₄)) - (v₃*(4qa₃*qb₄ - (4qa₁*qb₂) - (4qa₄*qb₃)))))) + λ₂*(qb₁*(v₂*(4qa₂*qb₁ - (4qa₁*qb₂) - (4qa₄*qb₃)) - (v₁*(4qa₄*qb₂ - (4qa₁*qb₃) - (4qa₂*qb₄))) - (v₃*(4qa₁*qb₁ + 4qa₂*qb₂ + 4qa₄*qb₄))) + qb₄*(v₃*(4qa₁*qb₄ - (4qa₂*qb₃) - (4qa₄*qb₁)) - (v₁*(4qa₂*qb₁ - (4qa₁*qb₂) - (4qa₄*qb₃))) - (v₂*(4qa₄*qb₂ - (4qa₁*qb₃) - (4qa₂*qb₄)))) - (qb₂*(v₁*(4qa₁*qb₄ - (4qa₂*qb₃) - (4qa₄*qb₁)) + v₂*(4qa₁*qb₁ + 4qa₂*qb₂ + 4qa₄*qb₄) + v₃*(4qa₂*qb₁ - (4qa₁*qb₂) - (4qa₄*qb₃)))) - (qb₃*(v₁*(4qa₁*qb₁ + 4qa₂*qb₂ + 4qa₄*qb₄) - (v₂*(4qa₁*qb₄ - (4qa₂*qb₃) - (4qa₄*qb₁))) - (v₃*(4qa₄*qb₂ - (4qa₁*qb₃) - (4qa₂*qb₄)))))) + λ₃*(qb₁*(v₂*(4qa₁*qb₁ + 4qa₂*qb₂ + 4qa₃*qb₃) - (v₁*(4qa₂*qb₃ - (4qa₁*qb₄) - (4qa₃*qb₂))) - (v₃*(4qa₁*qb₂ - (4qa₂*qb₁) - (4qa₃*qb₄)))) + qb₄*(v₃*(4qa₃*qb₁ - (4qa₁*qb₃) - (4qa₂*qb₄)) - (v₁*(4qa₁*qb₁ + 4qa₂*qb₂ + 4qa₃*qb₃)) - (v₂*(4qa₂*qb₃ - (4qa₁*qb₄) - (4qa₃*qb₂)))) - (qb₂*(v₁*(4qa₃*qb₁ - (4qa₁*qb₃) - (4qa₂*qb₄)) + v₂*(4qa₁*qb₂ - (4qa₂*qb₁) - (4qa₃*qb₄)) + v₃*(4qa₁*qb₁ + 4qa₂*qb₂ + 4qa₃*qb₃))) - (qb₃*(v₁*(4qa₁*qb₂ - (4qa₂*qb₁) - (4qa₃*qb₄)) - (v₂*(4qa₃*qb₁ - (4qa₁*qb₃) - (4qa₂*qb₄))) - (v₃*(4qa₂*qb₃ - (4qa₁*qb₄) - (4qa₃*qb₂))))))
    dG[4, 5] = λ₁*(qb₁*(v₂*(4qa₂*qb₃ + 4qa₄*qb₁ - (4qa₃*qb₂)) - (v₁*(-4qa₂*qb₂ - (4qa₃*qb₃) - (4qa₄*qb₄))) - (v₃*(4qa₃*qb₁ + 4qa₄*qb₂ - (4qa₂*qb₄)))) + qb₄*(v₃*(4qa₂*qb₁ + 4qa₃*qb₄ - (4qa₄*qb₃)) - (v₁*(4qa₂*qb₃ + 4qa₄*qb₁ - (4qa₃*qb₂))) - (v₂*(-4qa₂*qb₂ - (4qa₃*qb₃) - (4qa₄*qb₄)))) - (qb₂*(v₁*(4qa₂*qb₁ + 4qa₃*qb₄ - (4qa₄*qb₃)) + v₂*(4qa₃*qb₁ + 4qa₄*qb₂ - (4qa₂*qb₄)) + v₃*(4qa₂*qb₃ + 4qa₄*qb₁ - (4qa₃*qb₂)))) - (qb₃*(v₁*(4qa₃*qb₁ + 4qa₄*qb₂ - (4qa₂*qb₄)) - (v₂*(4qa₂*qb₁ + 4qa₃*qb₄ - (4qa₄*qb₃))) - (v₃*(-4qa₂*qb₂ - (4qa₃*qb₃) - (4qa₄*qb₄)))))) + λ₂*(qb₁*(v₂*(4qa₁*qb₁ + 4qa₂*qb₂ + 4qa₃*qb₃) - (v₁*(4qa₂*qb₃ - (4qa₁*qb₄) - (4qa₃*qb₂))) - (v₃*(4qa₁*qb₂ - (4qa₂*qb₁) - (4qa₃*qb₄)))) + qb₄*(v₃*(4qa₃*qb₁ - (4qa₁*qb₃) - (4qa₂*qb₄)) - (v₁*(4qa₁*qb₁ + 4qa₂*qb₂ + 4qa₃*qb₃)) - (v₂*(4qa₂*qb₃ - (4qa₁*qb₄) - (4qa₃*qb₂)))) - (qb₂*(v₁*(4qa₃*qb₁ - (4qa₁*qb₃) - (4qa₂*qb₄)) + v₂*(4qa₁*qb₂ - (4qa₂*qb₁) - (4qa₃*qb₄)) + v₃*(4qa₁*qb₁ + 4qa₂*qb₂ + 4qa₃*qb₃))) - (qb₃*(v₁*(4qa₁*qb₂ - (4qa₂*qb₁) - (4qa₃*qb₄)) - (v₂*(4qa₃*qb₁ - (4qa₁*qb₃) - (4qa₂*qb₄))) - (v₃*(4qa₂*qb₃ - (4qa₁*qb₄) - (4qa₃*qb₂)))))) + λ₃*(qb₁*(v₂*(4qa₁*qb₂ + 4qa₄*qb₃ - (4qa₂*qb₁)) - (v₁*(4qa₁*qb₃ + 4qa₂*qb₄ - (4qa₄*qb₂))) - (v₃*(-4qa₁*qb₁ - (4qa₂*qb₂) - (4qa₄*qb₄)))) + qb₄*(v₃*(4qa₂*qb₃ + 4qa₄*qb₁ - (4qa₁*qb₄)) - (v₁*(4qa₁*qb₂ + 4qa₄*qb₃ - (4qa₂*qb₁))) - (v₂*(4qa₁*qb₃ + 4qa₂*qb₄ - (4qa₄*qb₂)))) - (qb₂*(v₁*(4qa₂*qb₃ + 4qa₄*qb₁ - (4qa₁*qb₄)) + v₂*(-4qa₁*qb₁ - (4qa₂*qb₂) - (4qa₄*qb₄)) + v₃*(4qa₁*qb₂ + 4qa₄*qb₃ - (4qa₂*qb₁)))) - (qb₃*(v₁*(-4qa₁*qb₁ - (4qa₂*qb₂) - (4qa₄*qb₄)) - (v₂*(4qa₂*qb₃ + 4qa₄*qb₁ - (4qa₁*qb₄))) - (v₃*(4qa₁*qb₃ + 4qa₂*qb₄ - (4qa₄*qb₂))))))
    dG[4, 6] = λ₁*(qb₁*(v₂*(-4qa₁*qb₁ - (4qa₂*qb₂) - (4qa₃*qb₃)) - (v₁*(4qa₁*qb₄ + 4qa₃*qb₂ - (4qa₂*qb₃))) - (v₃*(4qa₂*qb₁ + 4qa₃*qb₄ - (4qa₁*qb₂)))) + qb₄*(v₃*(4qa₁*qb₃ + 4qa₂*qb₄ - (4qa₃*qb₁)) - (v₁*(-4qa₁*qb₁ - (4qa₂*qb₂) - (4qa₃*qb₃))) - (v₂*(4qa₁*qb₄ + 4qa₃*qb₂ - (4qa₂*qb₃)))) - (qb₂*(v₁*(4qa₁*qb₃ + 4qa₂*qb₄ - (4qa₃*qb₁)) + v₂*(4qa₂*qb₁ + 4qa₃*qb₄ - (4qa₁*qb₂)) + v₃*(-4qa₁*qb₁ - (4qa₂*qb₂) - (4qa₃*qb₃)))) - (qb₃*(v₁*(4qa₂*qb₁ + 4qa₃*qb₄ - (4qa₁*qb₂)) - (v₂*(4qa₁*qb₃ + 4qa₂*qb₄ - (4qa₃*qb₁))) - (v₃*(4qa₁*qb₄ + 4qa₃*qb₂ - (4qa₂*qb₃)))))) + λ₂*(qb₁*(v₂*(4qa₂*qb₃ + 4qa₄*qb₁ - (4qa₃*qb₂)) - (v₁*(-4qa₂*qb₂ - (4qa₃*qb₃) - (4qa₄*qb₄))) - (v₃*(4qa₃*qb₁ + 4qa₄*qb₂ - (4qa₂*qb₄)))) + qb₄*(v₃*(4qa₂*qb₁ + 4qa₃*qb₄ - (4qa₄*qb₃)) - (v₁*(4qa₂*qb₃ + 4qa₄*qb₁ - (4qa₃*qb₂))) - (v₂*(-4qa₂*qb₂ - (4qa₃*qb₃) - (4qa₄*qb₄)))) - (qb₂*(v₁*(4qa₂*qb₁ + 4qa₃*qb₄ - (4qa₄*qb₃)) + v₂*(4qa₃*qb₁ + 4qa₄*qb₂ - (4qa₂*qb₄)) + v₃*(4qa₂*qb₃ + 4qa₄*qb₁ - (4qa₃*qb₂)))) - (qb₃*(v₁*(4qa₃*qb₁ + 4qa₄*qb₂ - (4qa₂*qb₄)) - (v₂*(4qa₂*qb₁ + 4qa₃*qb₄ - (4qa₄*qb₃))) - (v₃*(-4qa₂*qb₂ - (4qa₃*qb₃) - (4qa₄*qb₄)))))) + λ₃*(qb₁*(v₂*(4qa₁*qb₃ - (4qa₃*qb₁) - (4qa₄*qb₂)) - (v₁*(4qa₃*qb₄ - (4qa₁*qb₂) - (4qa₄*qb₃))) - (v₃*(4qa₄*qb₁ - (4qa₁*qb₄) - (4qa₃*qb₂)))) + qb₄*(v₃*(4qa₁*qb₁ + 4qa₃*qb₃ + 4qa₄*qb₄) - (v₁*(4qa₁*qb₃ - (4qa₃*qb₁) - (4qa₄*qb₂))) - (v₂*(4qa₃*qb₄ - (4qa₁*qb₂) - (4qa₄*qb₃)))) - (qb₂*(v₁*(4qa₁*qb₁ + 4qa₃*qb₃ + 4qa₄*qb₄) + v₂*(4qa₄*qb₁ - (4qa₁*qb₄) - (4qa₃*qb₂)) + v₃*(4qa₁*qb₃ - (4qa₃*qb₁) - (4qa₄*qb₂)))) - (qb₃*(v₁*(4qa₄*qb₁ - (4qa₁*qb₄) - (4qa₃*qb₂)) - (v₂*(4qa₁*qb₁ + 4qa₃*qb₃ + 4qa₄*qb₄)) - (v₃*(4qa₃*qb₄ - (4qa₁*qb₂) - (4qa₄*qb₃))))))
    dG[4, 7] = λ₁*(qb₁*(v₂*(4qa₂*qb₁ - (4qa₁*qb₂) - (4qa₄*qb₃)) - (v₁*(4qa₄*qb₂ - (4qa₁*qb₃) - (4qa₂*qb₄))) - (v₃*(4qa₁*qb₁ + 4qa₂*qb₂ + 4qa₄*qb₄))) + qb₄*(v₃*(4qa₁*qb₄ - (4qa₂*qb₃) - (4qa₄*qb₁)) - (v₁*(4qa₂*qb₁ - (4qa₁*qb₂) - (4qa₄*qb₃))) - (v₂*(4qa₄*qb₂ - (4qa₁*qb₃) - (4qa₂*qb₄)))) - (qb₂*(v₁*(4qa₁*qb₄ - (4qa₂*qb₃) - (4qa₄*qb₁)) + v₂*(4qa₁*qb₁ + 4qa₂*qb₂ + 4qa₄*qb₄) + v₃*(4qa₂*qb₁ - (4qa₁*qb₂) - (4qa₄*qb₃)))) - (qb₃*(v₁*(4qa₁*qb₁ + 4qa₂*qb₂ + 4qa₄*qb₄) - (v₂*(4qa₁*qb₄ - (4qa₂*qb₃) - (4qa₄*qb₁))) - (v₃*(4qa₄*qb₂ - (4qa₁*qb₃) - (4qa₂*qb₄)))))) + λ₂*(qb₁*(v₂*(4qa₃*qb₁ + 4qa₄*qb₂ - (4qa₁*qb₃)) - (v₁*(4qa₁*qb₂ + 4qa₄*qb₃ - (4qa₃*qb₄))) - (v₃*(4qa₁*qb₄ + 4qa₃*qb₂ - (4qa₄*qb₁)))) + qb₄*(v₃*(-4qa₁*qb₁ - (4qa₃*qb₃) - (4qa₄*qb₄)) - (v₁*(4qa₃*qb₁ + 4qa₄*qb₂ - (4qa₁*qb₃))) - (v₂*(4qa₁*qb₂ + 4qa₄*qb₃ - (4qa₃*qb₄)))) - (qb₂*(v₁*(-4qa₁*qb₁ - (4qa₃*qb₃) - (4qa₄*qb₄)) + v₂*(4qa₁*qb₄ + 4qa₃*qb₂ - (4qa₄*qb₁)) + v₃*(4qa₃*qb₁ + 4qa₄*qb₂ - (4qa₁*qb₃)))) - (qb₃*(v₁*(4qa₁*qb₄ + 4qa₃*qb₂ - (4qa₄*qb₁)) - (v₂*(-4qa₁*qb₁ - (4qa₃*qb₃) - (4qa₄*qb₄))) - (v₃*(4qa₁*qb₂ + 4qa₄*qb₃ - (4qa₃*qb₄)))))) + λ₃*(qb₁*(v₂*(4qa₂*qb₃ + 4qa₄*qb₁ - (4qa₃*qb₂)) - (v₁*(-4qa₂*qb₂ - (4qa₃*qb₃) - (4qa₄*qb₄))) - (v₃*(4qa₃*qb₁ + 4qa₄*qb₂ - (4qa₂*qb₄)))) + qb₄*(v₃*(4qa₂*qb₁ + 4qa₃*qb₄ - (4qa₄*qb₃)) - (v₁*(4qa₂*qb₃ + 4qa₄*qb₁ - (4qa₃*qb₂))) - (v₂*(-4qa₂*qb₂ - (4qa₃*qb₃) - (4qa₄*qb₄)))) - (qb₂*(v₁*(4qa₂*qb₁ + 4qa₃*qb₄ - (4qa₄*qb₃)) + v₂*(4qa₃*qb₁ + 4qa₄*qb₂ - (4qa₂*qb₄)) + v₃*(4qa₂*qb₃ + 4qa₄*qb₁ - (4qa₃*qb₂)))) - (qb₃*(v₁*(4qa₃*qb₁ + 4qa₄*qb₂ - (4qa₂*qb₄)) - (v₂*(4qa₂*qb₁ + 4qa₃*qb₄ - (4qa₄*qb₃))) - (v₃*(-4qa₂*qb₂ - (4qa₃*qb₃) - (4qa₄*qb₄))))))
    dG[5, 1] = 0
    dG[5, 2] = 0
    dG[5, 3] = 0
    dG[5, 4] = λ₁*(qb₁*(v₃*(4qa₁*qb₁ + 4qa₃*qb₃ + 4qa₄*qb₄) - (v₁*(4qa₁*qb₃ - (4qa₃*qb₁) - (4qa₄*qb₂))) - (v₂*(4qa₃*qb₄ - (4qa₁*qb₂) - (4qa₄*qb₃)))) + qb₂*(v₁*(4qa₄*qb₁ - (4qa₁*qb₄) - (4qa₃*qb₂)) - (v₂*(4qa₁*qb₁ + 4qa₃*qb₃ + 4qa₄*qb₄)) - (v₃*(4qa₃*qb₄ - (4qa₁*qb₂) - (4qa₄*qb₃)))) - (qb₃*(v₁*(4qa₁*qb₁ + 4qa₃*qb₃ + 4qa₄*qb₄) + v₂*(4qa₄*qb₁ - (4qa₁*qb₄) - (4qa₃*qb₂)) + v₃*(4qa₁*qb₃ - (4qa₃*qb₁) - (4qa₄*qb₂)))) - (qb₄*(v₂*(4qa₁*qb₃ - (4qa₃*qb₁) - (4qa₄*qb₂)) - (v₁*(4qa₃*qb₄ - (4qa₁*qb₂) - (4qa₄*qb₃))) - (v₃*(4qa₄*qb₁ - (4qa₁*qb₄) - (4qa₃*qb₂)))))) + λ₂*(qb₁*(v₃*(4qa₁*qb₄ - (4qa₂*qb₃) - (4qa₄*qb₁)) - (v₁*(4qa₂*qb₁ - (4qa₁*qb₂) - (4qa₄*qb₃))) - (v₂*(4qa₄*qb₂ - (4qa₁*qb₃) - (4qa₂*qb₄)))) + qb₂*(v₁*(4qa₁*qb₁ + 4qa₂*qb₂ + 4qa₄*qb₄) - (v₂*(4qa₁*qb₄ - (4qa₂*qb₃) - (4qa₄*qb₁))) - (v₃*(4qa₄*qb₂ - (4qa₁*qb₃) - (4qa₂*qb₄)))) - (qb₃*(v₁*(4qa₁*qb₄ - (4qa₂*qb₃) - (4qa₄*qb₁)) + v₂*(4qa₁*qb₁ + 4qa₂*qb₂ + 4qa₄*qb₄) + v₃*(4qa₂*qb₁ - (4qa₁*qb₂) - (4qa₄*qb₃)))) - (qb₄*(v₂*(4qa₂*qb₁ - (4qa₁*qb₂) - (4qa₄*qb₃)) - (v₁*(4qa₄*qb₂ - (4qa₁*qb₃) - (4qa₂*qb₄))) - (v₃*(4qa₁*qb₁ + 4qa₂*qb₂ + 4qa₄*qb₄))))) + λ₃*(qb₁*(v₃*(4qa₃*qb₁ - (4qa₁*qb₃) - (4qa₂*qb₄)) - (v₁*(4qa₁*qb₁ + 4qa₂*qb₂ + 4qa₃*qb₃)) - (v₂*(4qa₂*qb₃ - (4qa₁*qb₄) - (4qa₃*qb₂)))) + qb₂*(v₁*(4qa₁*qb₂ - (4qa₂*qb₁) - (4qa₃*qb₄)) - (v₂*(4qa₃*qb₁ - (4qa₁*qb₃) - (4qa₂*qb₄))) - (v₃*(4qa₂*qb₃ - (4qa₁*qb₄) - (4qa₃*qb₂)))) - (qb₃*(v₁*(4qa₃*qb₁ - (4qa₁*qb₃) - (4qa₂*qb₄)) + v₂*(4qa₁*qb₂ - (4qa₂*qb₁) - (4qa₃*qb₄)) + v₃*(4qa₁*qb₁ + 4qa₂*qb₂ + 4qa₃*qb₃))) - (qb₄*(v₂*(4qa₁*qb₁ + 4qa₂*qb₂ + 4qa₃*qb₃) - (v₁*(4qa₂*qb₃ - (4qa₁*qb₄) - (4qa₃*qb₂))) - (v₃*(4qa₁*qb₂ - (4qa₂*qb₁) - (4qa₃*qb₄))))))
    dG[5, 5] = λ₁*(qb₁*(v₃*(4qa₂*qb₁ + 4qa₃*qb₄ - (4qa₄*qb₃)) - (v₁*(4qa₂*qb₃ + 4qa₄*qb₁ - (4qa₃*qb₂))) - (v₂*(-4qa₂*qb₂ - (4qa₃*qb₃) - (4qa₄*qb₄)))) + qb₂*(v₁*(4qa₃*qb₁ + 4qa₄*qb₂ - (4qa₂*qb₄)) - (v₂*(4qa₂*qb₁ + 4qa₃*qb₄ - (4qa₄*qb₃))) - (v₃*(-4qa₂*qb₂ - (4qa₃*qb₃) - (4qa₄*qb₄)))) - (qb₃*(v₁*(4qa₂*qb₁ + 4qa₃*qb₄ - (4qa₄*qb₃)) + v₂*(4qa₃*qb₁ + 4qa₄*qb₂ - (4qa₂*qb₄)) + v₃*(4qa₂*qb₃ + 4qa₄*qb₁ - (4qa₃*qb₂)))) - (qb₄*(v₂*(4qa₂*qb₃ + 4qa₄*qb₁ - (4qa₃*qb₂)) - (v₁*(-4qa₂*qb₂ - (4qa₃*qb₃) - (4qa₄*qb₄))) - (v₃*(4qa₃*qb₁ + 4qa₄*qb₂ - (4qa₂*qb₄)))))) + λ₂*(qb₁*(v₃*(4qa₃*qb₁ - (4qa₁*qb₃) - (4qa₂*qb₄)) - (v₁*(4qa₁*qb₁ + 4qa₂*qb₂ + 4qa₃*qb₃)) - (v₂*(4qa₂*qb₃ - (4qa₁*qb₄) - (4qa₃*qb₂)))) + qb₂*(v₁*(4qa₁*qb₂ - (4qa₂*qb₁) - (4qa₃*qb₄)) - (v₂*(4qa₃*qb₁ - (4qa₁*qb₃) - (4qa₂*qb₄))) - (v₃*(4qa₂*qb₃ - (4qa₁*qb₄) - (4qa₃*qb₂)))) - (qb₃*(v₁*(4qa₃*qb₁ - (4qa₁*qb₃) - (4qa₂*qb₄)) + v₂*(4qa₁*qb₂ - (4qa₂*qb₁) - (4qa₃*qb₄)) + v₃*(4qa₁*qb₁ + 4qa₂*qb₂ + 4qa₃*qb₃))) - (qb₄*(v₂*(4qa₁*qb₁ + 4qa₂*qb₂ + 4qa₃*qb₃) - (v₁*(4qa₂*qb₃ - (4qa₁*qb₄) - (4qa₃*qb₂))) - (v₃*(4qa₁*qb₂ - (4qa₂*qb₁) - (4qa₃*qb₄)))))) + λ₃*(qb₁*(v₃*(4qa₂*qb₃ + 4qa₄*qb₁ - (4qa₁*qb₄)) - (v₁*(4qa₁*qb₂ + 4qa₄*qb₃ - (4qa₂*qb₁))) - (v₂*(4qa₁*qb₃ + 4qa₂*qb₄ - (4qa₄*qb₂)))) + qb₂*(v₁*(-4qa₁*qb₁ - (4qa₂*qb₂) - (4qa₄*qb₄)) - (v₂*(4qa₂*qb₃ + 4qa₄*qb₁ - (4qa₁*qb₄))) - (v₃*(4qa₁*qb₃ + 4qa₂*qb₄ - (4qa₄*qb₂)))) - (qb₃*(v₁*(4qa₂*qb₃ + 4qa₄*qb₁ - (4qa₁*qb₄)) + v₂*(-4qa₁*qb₁ - (4qa₂*qb₂) - (4qa₄*qb₄)) + v₃*(4qa₁*qb₂ + 4qa₄*qb₃ - (4qa₂*qb₁)))) - (qb₄*(v₂*(4qa₁*qb₂ + 4qa₄*qb₃ - (4qa₂*qb₁)) - (v₁*(4qa₁*qb₃ + 4qa₂*qb₄ - (4qa₄*qb₂))) - (v₃*(-4qa₁*qb₁ - (4qa₂*qb₂) - (4qa₄*qb₄))))))
    dG[5, 6] = λ₁*(qb₁*(v₃*(4qa₁*qb₃ + 4qa₂*qb₄ - (4qa₃*qb₁)) - (v₁*(-4qa₁*qb₁ - (4qa₂*qb₂) - (4qa₃*qb₃))) - (v₂*(4qa₁*qb₄ + 4qa₃*qb₂ - (4qa₂*qb₃)))) + qb₂*(v₁*(4qa₂*qb₁ + 4qa₃*qb₄ - (4qa₁*qb₂)) - (v₂*(4qa₁*qb₃ + 4qa₂*qb₄ - (4qa₃*qb₁))) - (v₃*(4qa₁*qb₄ + 4qa₃*qb₂ - (4qa₂*qb₃)))) - (qb₃*(v₁*(4qa₁*qb₃ + 4qa₂*qb₄ - (4qa₃*qb₁)) + v₂*(4qa₂*qb₁ + 4qa₃*qb₄ - (4qa₁*qb₂)) + v₃*(-4qa₁*qb₁ - (4qa₂*qb₂) - (4qa₃*qb₃)))) - (qb₄*(v₂*(-4qa₁*qb₁ - (4qa₂*qb₂) - (4qa₃*qb₃)) - (v₁*(4qa₁*qb₄ + 4qa₃*qb₂ - (4qa₂*qb₃))) - (v₃*(4qa₂*qb₁ + 4qa₃*qb₄ - (4qa₁*qb₂)))))) + λ₂*(qb₁*(v₃*(4qa₂*qb₁ + 4qa₃*qb₄ - (4qa₄*qb₃)) - (v₁*(4qa₂*qb₃ + 4qa₄*qb₁ - (4qa₃*qb₂))) - (v₂*(-4qa₂*qb₂ - (4qa₃*qb₃) - (4qa₄*qb₄)))) + qb₂*(v₁*(4qa₃*qb₁ + 4qa₄*qb₂ - (4qa₂*qb₄)) - (v₂*(4qa₂*qb₁ + 4qa₃*qb₄ - (4qa₄*qb₃))) - (v₃*(-4qa₂*qb₂ - (4qa₃*qb₃) - (4qa₄*qb₄)))) - (qb₃*(v₁*(4qa₂*qb₁ + 4qa₃*qb₄ - (4qa₄*qb₃)) + v₂*(4qa₃*qb₁ + 4qa₄*qb₂ - (4qa₂*qb₄)) + v₃*(4qa₂*qb₃ + 4qa₄*qb₁ - (4qa₃*qb₂)))) - (qb₄*(v₂*(4qa₂*qb₃ + 4qa₄*qb₁ - (4qa₃*qb₂)) - (v₁*(-4qa₂*qb₂ - (4qa₃*qb₃) - (4qa₄*qb₄))) - (v₃*(4qa₃*qb₁ + 4qa₄*qb₂ - (4qa₂*qb₄)))))) + λ₃*(qb₁*(v₃*(4qa₁*qb₁ + 4qa₃*qb₃ + 4qa₄*qb₄) - (v₁*(4qa₁*qb₃ - (4qa₃*qb₁) - (4qa₄*qb₂))) - (v₂*(4qa₃*qb₄ - (4qa₁*qb₂) - (4qa₄*qb₃)))) + qb₂*(v₁*(4qa₄*qb₁ - (4qa₁*qb₄) - (4qa₃*qb₂)) - (v₂*(4qa₁*qb₁ + 4qa₃*qb₃ + 4qa₄*qb₄)) - (v₃*(4qa₃*qb₄ - (4qa₁*qb₂) - (4qa₄*qb₃)))) - (qb₃*(v₁*(4qa₁*qb₁ + 4qa₃*qb₃ + 4qa₄*qb₄) + v₂*(4qa₄*qb₁ - (4qa₁*qb₄) - (4qa₃*qb₂)) + v₃*(4qa₁*qb₃ - (4qa₃*qb₁) - (4qa₄*qb₂)))) - (qb₄*(v₂*(4qa₁*qb₃ - (4qa₃*qb₁) - (4qa₄*qb₂)) - (v₁*(4qa₃*qb₄ - (4qa₁*qb₂) - (4qa₄*qb₃))) - (v₃*(4qa₄*qb₁ - (4qa₁*qb₄) - (4qa₃*qb₂))))))
    dG[5, 7] = λ₁*(qb₁*(v₃*(4qa₁*qb₄ - (4qa₂*qb₃) - (4qa₄*qb₁)) - (v₁*(4qa₂*qb₁ - (4qa₁*qb₂) - (4qa₄*qb₃))) - (v₂*(4qa₄*qb₂ - (4qa₁*qb₃) - (4qa₂*qb₄)))) + qb₂*(v₁*(4qa₁*qb₁ + 4qa₂*qb₂ + 4qa₄*qb₄) - (v₂*(4qa₁*qb₄ - (4qa₂*qb₃) - (4qa₄*qb₁))) - (v₃*(4qa₄*qb₂ - (4qa₁*qb₃) - (4qa₂*qb₄)))) - (qb₃*(v₁*(4qa₁*qb₄ - (4qa₂*qb₃) - (4qa₄*qb₁)) + v₂*(4qa₁*qb₁ + 4qa₂*qb₂ + 4qa₄*qb₄) + v₃*(4qa₂*qb₁ - (4qa₁*qb₂) - (4qa₄*qb₃)))) - (qb₄*(v₂*(4qa₂*qb₁ - (4qa₁*qb₂) - (4qa₄*qb₃)) - (v₁*(4qa₄*qb₂ - (4qa₁*qb₃) - (4qa₂*qb₄))) - (v₃*(4qa₁*qb₁ + 4qa₂*qb₂ + 4qa₄*qb₄))))) + λ₂*(qb₁*(v₃*(-4qa₁*qb₁ - (4qa₃*qb₃) - (4qa₄*qb₄)) - (v₁*(4qa₃*qb₁ + 4qa₄*qb₂ - (4qa₁*qb₃))) - (v₂*(4qa₁*qb₂ + 4qa₄*qb₃ - (4qa₃*qb₄)))) + qb₂*(v₁*(4qa₁*qb₄ + 4qa₃*qb₂ - (4qa₄*qb₁)) - (v₂*(-4qa₁*qb₁ - (4qa₃*qb₃) - (4qa₄*qb₄))) - (v₃*(4qa₁*qb₂ + 4qa₄*qb₃ - (4qa₃*qb₄)))) - (qb₃*(v₁*(-4qa₁*qb₁ - (4qa₃*qb₃) - (4qa₄*qb₄)) + v₂*(4qa₁*qb₄ + 4qa₃*qb₂ - (4qa₄*qb₁)) + v₃*(4qa₃*qb₁ + 4qa₄*qb₂ - (4qa₁*qb₃)))) - (qb₄*(v₂*(4qa₃*qb₁ + 4qa₄*qb₂ - (4qa₁*qb₃)) - (v₁*(4qa₁*qb₂ + 4qa₄*qb₃ - (4qa₃*qb₄))) - (v₃*(4qa₁*qb₄ + 4qa₃*qb₂ - (4qa₄*qb₁)))))) + λ₃*(qb₁*(v₃*(4qa₂*qb₁ + 4qa₃*qb₄ - (4qa₄*qb₃)) - (v₁*(4qa₂*qb₃ + 4qa₄*qb₁ - (4qa₃*qb₂))) - (v₂*(-4qa₂*qb₂ - (4qa₃*qb₃) - (4qa₄*qb₄)))) + qb₂*(v₁*(4qa₃*qb₁ + 4qa₄*qb₂ - (4qa₂*qb₄)) - (v₂*(4qa₂*qb₁ + 4qa₃*qb₄ - (4qa₄*qb₃))) - (v₃*(-4qa₂*qb₂ - (4qa₃*qb₃) - (4qa₄*qb₄)))) - (qb₃*(v₁*(4qa₂*qb₁ + 4qa₃*qb₄ - (4qa₄*qb₃)) + v₂*(4qa₃*qb₁ + 4qa₄*qb₂ - (4qa₂*qb₄)) + v₃*(4qa₂*qb₃ + 4qa₄*qb₁ - (4qa₃*qb₂)))) - (qb₄*(v₂*(4qa₂*qb₃ + 4qa₄*qb₁ - (4qa₃*qb₂)) - (v₁*(-4qa₂*qb₂ - (4qa₃*qb₃) - (4qa₄*qb₄))) - (v₃*(4qa₃*qb₁ + 4qa₄*qb₂ - (4qa₂*qb₄))))))
    dG[6, 1] = 0
    dG[6, 2] = 0
    dG[6, 3] = 0
    dG[6, 4] = λ₁*(qb₁*(v₁*(4qa₄*qb₁ - (4qa₁*qb₄) - (4qa₃*qb₂)) - (v₂*(4qa₁*qb₁ + 4qa₃*qb₃ + 4qa₄*qb₄)) - (v₃*(4qa₃*qb₄ - (4qa₁*qb₂) - (4qa₄*qb₃)))) + qb₃*(v₂*(4qa₁*qb₃ - (4qa₃*qb₁) - (4qa₄*qb₂)) - (v₁*(4qa₃*qb₄ - (4qa₁*qb₂) - (4qa₄*qb₃))) - (v₃*(4qa₄*qb₁ - (4qa₁*qb₄) - (4qa₃*qb₂)))) - (qb₂*(v₃*(4qa₁*qb₁ + 4qa₃*qb₃ + 4qa₄*qb₄) - (v₁*(4qa₁*qb₃ - (4qa₃*qb₁) - (4qa₄*qb₂))) - (v₂*(4qa₃*qb₄ - (4qa₁*qb₂) - (4qa₄*qb₃))))) - (qb₄*(v₁*(4qa₁*qb₁ + 4qa₃*qb₃ + 4qa₄*qb₄) + v₂*(4qa₄*qb₁ - (4qa₁*qb₄) - (4qa₃*qb₂)) + v₃*(4qa₁*qb₃ - (4qa₃*qb₁) - (4qa₄*qb₂))))) + λ₂*(qb₁*(v₁*(4qa₁*qb₁ + 4qa₂*qb₂ + 4qa₄*qb₄) - (v₂*(4qa₁*qb₄ - (4qa₂*qb₃) - (4qa₄*qb₁))) - (v₃*(4qa₄*qb₂ - (4qa₁*qb₃) - (4qa₂*qb₄)))) + qb₃*(v₂*(4qa₂*qb₁ - (4qa₁*qb₂) - (4qa₄*qb₃)) - (v₁*(4qa₄*qb₂ - (4qa₁*qb₃) - (4qa₂*qb₄))) - (v₃*(4qa₁*qb₁ + 4qa₂*qb₂ + 4qa₄*qb₄))) - (qb₂*(v₃*(4qa₁*qb₄ - (4qa₂*qb₃) - (4qa₄*qb₁)) - (v₁*(4qa₂*qb₁ - (4qa₁*qb₂) - (4qa₄*qb₃))) - (v₂*(4qa₄*qb₂ - (4qa₁*qb₃) - (4qa₂*qb₄))))) - (qb₄*(v₁*(4qa₁*qb₄ - (4qa₂*qb₃) - (4qa₄*qb₁)) + v₂*(4qa₁*qb₁ + 4qa₂*qb₂ + 4qa₄*qb₄) + v₃*(4qa₂*qb₁ - (4qa₁*qb₂) - (4qa₄*qb₃))))) + λ₃*(qb₁*(v₁*(4qa₁*qb₂ - (4qa₂*qb₁) - (4qa₃*qb₄)) - (v₂*(4qa₃*qb₁ - (4qa₁*qb₃) - (4qa₂*qb₄))) - (v₃*(4qa₂*qb₃ - (4qa₁*qb₄) - (4qa₃*qb₂)))) + qb₃*(v₂*(4qa₁*qb₁ + 4qa₂*qb₂ + 4qa₃*qb₃) - (v₁*(4qa₂*qb₃ - (4qa₁*qb₄) - (4qa₃*qb₂))) - (v₃*(4qa₁*qb₂ - (4qa₂*qb₁) - (4qa₃*qb₄)))) - (qb₂*(v₃*(4qa₃*qb₁ - (4qa₁*qb₃) - (4qa₂*qb₄)) - (v₁*(4qa₁*qb₁ + 4qa₂*qb₂ + 4qa₃*qb₃)) - (v₂*(4qa₂*qb₃ - (4qa₁*qb₄) - (4qa₃*qb₂))))) - (qb₄*(v₁*(4qa₃*qb₁ - (4qa₁*qb₃) - (4qa₂*qb₄)) + v₂*(4qa₁*qb₂ - (4qa₂*qb₁) - (4qa₃*qb₄)) + v₃*(4qa₁*qb₁ + 4qa₂*qb₂ + 4qa₃*qb₃))))
    dG[6, 5] = λ₁*(qb₁*(v₁*(4qa₃*qb₁ + 4qa₄*qb₂ - (4qa₂*qb₄)) - (v₂*(4qa₂*qb₁ + 4qa₃*qb₄ - (4qa₄*qb₃))) - (v₃*(-4qa₂*qb₂ - (4qa₃*qb₃) - (4qa₄*qb₄)))) + qb₃*(v₂*(4qa₂*qb₃ + 4qa₄*qb₁ - (4qa₃*qb₂)) - (v₁*(-4qa₂*qb₂ - (4qa₃*qb₃) - (4qa₄*qb₄))) - (v₃*(4qa₃*qb₁ + 4qa₄*qb₂ - (4qa₂*qb₄)))) - (qb₂*(v₃*(4qa₂*qb₁ + 4qa₃*qb₄ - (4qa₄*qb₃)) - (v₁*(4qa₂*qb₃ + 4qa₄*qb₁ - (4qa₃*qb₂))) - (v₂*(-4qa₂*qb₂ - (4qa₃*qb₃) - (4qa₄*qb₄))))) - (qb₄*(v₁*(4qa₂*qb₁ + 4qa₃*qb₄ - (4qa₄*qb₃)) + v₂*(4qa₃*qb₁ + 4qa₄*qb₂ - (4qa₂*qb₄)) + v₃*(4qa₂*qb₃ + 4qa₄*qb₁ - (4qa₃*qb₂))))) + λ₂*(qb₁*(v₁*(4qa₁*qb₂ - (4qa₂*qb₁) - (4qa₃*qb₄)) - (v₂*(4qa₃*qb₁ - (4qa₁*qb₃) - (4qa₂*qb₄))) - (v₃*(4qa₂*qb₃ - (4qa₁*qb₄) - (4qa₃*qb₂)))) + qb₃*(v₂*(4qa₁*qb₁ + 4qa₂*qb₂ + 4qa₃*qb₃) - (v₁*(4qa₂*qb₃ - (4qa₁*qb₄) - (4qa₃*qb₂))) - (v₃*(4qa₁*qb₂ - (4qa₂*qb₁) - (4qa₃*qb₄)))) - (qb₂*(v₃*(4qa₃*qb₁ - (4qa₁*qb₃) - (4qa₂*qb₄)) - (v₁*(4qa₁*qb₁ + 4qa₂*qb₂ + 4qa₃*qb₃)) - (v₂*(4qa₂*qb₃ - (4qa₁*qb₄) - (4qa₃*qb₂))))) - (qb₄*(v₁*(4qa₃*qb₁ - (4qa₁*qb₃) - (4qa₂*qb₄)) + v₂*(4qa₁*qb₂ - (4qa₂*qb₁) - (4qa₃*qb₄)) + v₃*(4qa₁*qb₁ + 4qa₂*qb₂ + 4qa₃*qb₃)))) + λ₃*(qb₁*(v₁*(-4qa₁*qb₁ - (4qa₂*qb₂) - (4qa₄*qb₄)) - (v₂*(4qa₂*qb₃ + 4qa₄*qb₁ - (4qa₁*qb₄))) - (v₃*(4qa₁*qb₃ + 4qa₂*qb₄ - (4qa₄*qb₂)))) + qb₃*(v₂*(4qa₁*qb₂ + 4qa₄*qb₃ - (4qa₂*qb₁)) - (v₁*(4qa₁*qb₃ + 4qa₂*qb₄ - (4qa₄*qb₂))) - (v₃*(-4qa₁*qb₁ - (4qa₂*qb₂) - (4qa₄*qb₄)))) - (qb₂*(v₃*(4qa₂*qb₃ + 4qa₄*qb₁ - (4qa₁*qb₄)) - (v₁*(4qa₁*qb₂ + 4qa₄*qb₃ - (4qa₂*qb₁))) - (v₂*(4qa₁*qb₃ + 4qa₂*qb₄ - (4qa₄*qb₂))))) - (qb₄*(v₁*(4qa₂*qb₃ + 4qa₄*qb₁ - (4qa₁*qb₄)) + v₂*(-4qa₁*qb₁ - (4qa₂*qb₂) - (4qa₄*qb₄)) + v₃*(4qa₁*qb₂ + 4qa₄*qb₃ - (4qa₂*qb₁)))))
    dG[6, 6] = λ₁*(qb₁*(v₁*(4qa₂*qb₁ + 4qa₃*qb₄ - (4qa₁*qb₂)) - (v₂*(4qa₁*qb₃ + 4qa₂*qb₄ - (4qa₃*qb₁))) - (v₃*(4qa₁*qb₄ + 4qa₃*qb₂ - (4qa₂*qb₃)))) + qb₃*(v₂*(-4qa₁*qb₁ - (4qa₂*qb₂) - (4qa₃*qb₃)) - (v₁*(4qa₁*qb₄ + 4qa₃*qb₂ - (4qa₂*qb₃))) - (v₃*(4qa₂*qb₁ + 4qa₃*qb₄ - (4qa₁*qb₂)))) - (qb₂*(v₃*(4qa₁*qb₃ + 4qa₂*qb₄ - (4qa₃*qb₁)) - (v₁*(-4qa₁*qb₁ - (4qa₂*qb₂) - (4qa₃*qb₃))) - (v₂*(4qa₁*qb₄ + 4qa₃*qb₂ - (4qa₂*qb₃))))) - (qb₄*(v₁*(4qa₁*qb₃ + 4qa₂*qb₄ - (4qa₃*qb₁)) + v₂*(4qa₂*qb₁ + 4qa₃*qb₄ - (4qa₁*qb₂)) + v₃*(-4qa₁*qb₁ - (4qa₂*qb₂) - (4qa₃*qb₃))))) + λ₂*(qb₁*(v₁*(4qa₃*qb₁ + 4qa₄*qb₂ - (4qa₂*qb₄)) - (v₂*(4qa₂*qb₁ + 4qa₃*qb₄ - (4qa₄*qb₃))) - (v₃*(-4qa₂*qb₂ - (4qa₃*qb₃) - (4qa₄*qb₄)))) + qb₃*(v₂*(4qa₂*qb₃ + 4qa₄*qb₁ - (4qa₃*qb₂)) - (v₁*(-4qa₂*qb₂ - (4qa₃*qb₃) - (4qa₄*qb₄))) - (v₃*(4qa₃*qb₁ + 4qa₄*qb₂ - (4qa₂*qb₄)))) - (qb₂*(v₃*(4qa₂*qb₁ + 4qa₃*qb₄ - (4qa₄*qb₃)) - (v₁*(4qa₂*qb₃ + 4qa₄*qb₁ - (4qa₃*qb₂))) - (v₂*(-4qa₂*qb₂ - (4qa₃*qb₃) - (4qa₄*qb₄))))) - (qb₄*(v₁*(4qa₂*qb₁ + 4qa₃*qb₄ - (4qa₄*qb₃)) + v₂*(4qa₃*qb₁ + 4qa₄*qb₂ - (4qa₂*qb₄)) + v₃*(4qa₂*qb₃ + 4qa₄*qb₁ - (4qa₃*qb₂))))) + λ₃*(qb₁*(v₁*(4qa₄*qb₁ - (4qa₁*qb₄) - (4qa₃*qb₂)) - (v₂*(4qa₁*qb₁ + 4qa₃*qb₃ + 4qa₄*qb₄)) - (v₃*(4qa₃*qb₄ - (4qa₁*qb₂) - (4qa₄*qb₃)))) + qb₃*(v₂*(4qa₁*qb₃ - (4qa₃*qb₁) - (4qa₄*qb₂)) - (v₁*(4qa₃*qb₄ - (4qa₁*qb₂) - (4qa₄*qb₃))) - (v₃*(4qa₄*qb₁ - (4qa₁*qb₄) - (4qa₃*qb₂)))) - (qb₂*(v₃*(4qa₁*qb₁ + 4qa₃*qb₃ + 4qa₄*qb₄) - (v₁*(4qa₁*qb₃ - (4qa₃*qb₁) - (4qa₄*qb₂))) - (v₂*(4qa₃*qb₄ - (4qa₁*qb₂) - (4qa₄*qb₃))))) - (qb₄*(v₁*(4qa₁*qb₁ + 4qa₃*qb₃ + 4qa₄*qb₄) + v₂*(4qa₄*qb₁ - (4qa₁*qb₄) - (4qa₃*qb₂)) + v₃*(4qa₁*qb₃ - (4qa₃*qb₁) - (4qa₄*qb₂)))))
    dG[6, 7] = λ₁*(qb₁*(v₁*(4qa₁*qb₁ + 4qa₂*qb₂ + 4qa₄*qb₄) - (v₂*(4qa₁*qb₄ - (4qa₂*qb₃) - (4qa₄*qb₁))) - (v₃*(4qa₄*qb₂ - (4qa₁*qb₃) - (4qa₂*qb₄)))) + qb₃*(v₂*(4qa₂*qb₁ - (4qa₁*qb₂) - (4qa₄*qb₃)) - (v₁*(4qa₄*qb₂ - (4qa₁*qb₃) - (4qa₂*qb₄))) - (v₃*(4qa₁*qb₁ + 4qa₂*qb₂ + 4qa₄*qb₄))) - (qb₂*(v₃*(4qa₁*qb₄ - (4qa₂*qb₃) - (4qa₄*qb₁)) - (v₁*(4qa₂*qb₁ - (4qa₁*qb₂) - (4qa₄*qb₃))) - (v₂*(4qa₄*qb₂ - (4qa₁*qb₃) - (4qa₂*qb₄))))) - (qb₄*(v₁*(4qa₁*qb₄ - (4qa₂*qb₃) - (4qa₄*qb₁)) + v₂*(4qa₁*qb₁ + 4qa₂*qb₂ + 4qa₄*qb₄) + v₃*(4qa₂*qb₁ - (4qa₁*qb₂) - (4qa₄*qb₃))))) + λ₂*(qb₁*(v₁*(4qa₁*qb₄ + 4qa₃*qb₂ - (4qa₄*qb₁)) - (v₂*(-4qa₁*qb₁ - (4qa₃*qb₃) - (4qa₄*qb₄))) - (v₃*(4qa₁*qb₂ + 4qa₄*qb₃ - (4qa₃*qb₄)))) + qb₃*(v₂*(4qa₃*qb₁ + 4qa₄*qb₂ - (4qa₁*qb₃)) - (v₁*(4qa₁*qb₂ + 4qa₄*qb₃ - (4qa₃*qb₄))) - (v₃*(4qa₁*qb₄ + 4qa₃*qb₂ - (4qa₄*qb₁)))) - (qb₂*(v₃*(-4qa₁*qb₁ - (4qa₃*qb₃) - (4qa₄*qb₄)) - (v₁*(4qa₃*qb₁ + 4qa₄*qb₂ - (4qa₁*qb₃))) - (v₂*(4qa₁*qb₂ + 4qa₄*qb₃ - (4qa₃*qb₄))))) - (qb₄*(v₁*(-4qa₁*qb₁ - (4qa₃*qb₃) - (4qa₄*qb₄)) + v₂*(4qa₁*qb₄ + 4qa₃*qb₂ - (4qa₄*qb₁)) + v₃*(4qa₃*qb₁ + 4qa₄*qb₂ - (4qa₁*qb₃))))) + λ₃*(qb₁*(v₁*(4qa₃*qb₁ + 4qa₄*qb₂ - (4qa₂*qb₄)) - (v₂*(4qa₂*qb₁ + 4qa₃*qb₄ - (4qa₄*qb₃))) - (v₃*(-4qa₂*qb₂ - (4qa₃*qb₃) - (4qa₄*qb₄)))) + qb₃*(v₂*(4qa₂*qb₃ + 4qa₄*qb₁ - (4qa₃*qb₂)) - (v₁*(-4qa₂*qb₂ - (4qa₃*qb₃) - (4qa₄*qb₄))) - (v₃*(4qa₃*qb₁ + 4qa₄*qb₂ - (4qa₂*qb₄)))) - (qb₂*(v₃*(4qa₂*qb₁ + 4qa₃*qb₄ - (4qa₄*qb₃)) - (v₁*(4qa₂*qb₃ + 4qa₄*qb₁ - (4qa₃*qb₂))) - (v₂*(-4qa₂*qb₂ - (4qa₃*qb₃) - (4qa₄*qb₄))))) - (qb₄*(v₁*(4qa₂*qb₁ + 4qa₃*qb₄ - (4qa₄*qb₃)) + v₂*(4qa₃*qb₁ + 4qa₄*qb₂ - (4qa₂*qb₄)) + v₃*(4qa₂*qb₃ + 4qa₄*qb₁ - (4qa₃*qb₂)))))

    return dG
end

function _dGbb(joint::Translational{T,N}, xa::AbstractVector, qa::UnitQuaternion, xb::AbstractVector, qb::UnitQuaternion, λ::AbstractVector) where {T,N}
    xa₁, xa₂, xa₃ = xa
    qa₁, qa₂, qa₃, qa₄ = [qa.w, qa.x, qa.y, qa.z]
    xb₁, xb₂, xb₃ = xb
    qb₁, qb₂, qb₃, qb₄ = [qb.w, qb.x, qb.y, qb.z]
    v₁, v₂, v₃ = joint.vertices[2]
    λ₁, λ₂, λ₃ = λ

    dG = zeros(6, 7)

    dG[1, 1] = 0
    dG[1, 2] = 0
    dG[1, 3] = 0
    dG[1, 4] = 0
    dG[1, 5] = 0
    dG[1, 6] = 0
    dG[1, 7] = 0
    dG[2, 1] = 0
    dG[2, 2] = 0
    dG[2, 3] = 0
    dG[2, 4] = 0
    dG[2, 5] = 0
    dG[2, 6] = 0
    dG[2, 7] = 0
    dG[3, 1] = 0
    dG[3, 2] = 0
    dG[3, 3] = 0
    dG[3, 4] = 0
    dG[3, 5] = 0
    dG[3, 6] = 0
    dG[3, 7] = 0
    dG[4, 1] = 0
    dG[4, 2] = 0
    dG[4, 3] = 0
    dG[4, 4] = λ₁*(qb₁*(v₂*(4qa₂*qa₄ - (4qa₁*qa₃)) - (v₃*(4qa₁*qa₄ + 4qa₂*qa₃))) + qb₄*(v₃*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))) - (v₁*(4qa₂*qa₄ - (4qa₁*qa₃)))) + v₂*(qb₁*(4qa₂*qa₄ - (4qa₁*qa₃)) + qb₃*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))) - (qb₂*(4qa₁*qa₄ + 4qa₂*qa₃))) - (qb₂*(v₁*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))) + v₂*(4qa₁*qa₄ + 4qa₂*qa₃) + v₃*(4qa₂*qa₄ - (4qa₁*qa₃)))) - (qb₃*(v₁*(4qa₁*qa₄ + 4qa₂*qa₃) - (v₂*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2)))))) - (v₁*(-qb₂*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))) - (qb₃*(4qa₁*qa₄ + 4qa₂*qa₃)) - (qb₄*(4qa₂*qa₄ - (4qa₁*qa₃))))) - (v₃*(qb₁*(4qa₁*qa₄ + 4qa₂*qa₃) + qb₂*(4qa₂*qa₄ - (4qa₁*qa₃)) - (qb₄*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))))))) + λ₂*(qb₁*(v₂*(4qa₁*qa₂ + 4qa₃*qa₄) - (v₃*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2))))) + qb₄*(v₃*(4qa₂*qa₃ - (4qa₁*qa₄)) - (v₁*(4qa₁*qa₂ + 4qa₃*qa₄))) + v₂*(qb₁*(4qa₁*qa₂ + 4qa₃*qa₄) + qb₃*(4qa₂*qa₃ - (4qa₁*qa₄)) - (qb₂*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2))))) - (qb₂*(v₁*(4qa₂*qa₃ - (4qa₁*qa₄)) + v₂*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2))) + v₃*(4qa₁*qa₂ + 4qa₃*qa₄))) - (qb₃*(v₁*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2))) - (v₂*(4qa₂*qa₃ - (4qa₁*qa₄))))) - (v₁*(-qb₂*(4qa₂*qa₃ - (4qa₁*qa₄)) - (qb₃*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2)))) - (qb₄*(4qa₁*qa₂ + 4qa₃*qa₄)))) - (v₃*(qb₁*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2))) + qb₂*(4qa₁*qa₂ + 4qa₃*qa₄) - (qb₄*(4qa₂*qa₃ - (4qa₁*qa₄)))))) + λ₃*(qb₁*(v₂*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))) - (v₃*(4qa₃*qa₄ - (4qa₁*qa₂)))) + qb₄*(v₃*(4qa₁*qa₃ + 4qa₂*qa₄) - (v₁*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))))) + v₂*(qb₁*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))) + qb₃*(4qa₁*qa₃ + 4qa₂*qa₄) - (qb₂*(4qa₃*qa₄ - (4qa₁*qa₂)))) - (qb₂*(v₁*(4qa₁*qa₃ + 4qa₂*qa₄) + v₂*(4qa₃*qa₄ - (4qa₁*qa₂)) + v₃*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))))) - (qb₃*(v₁*(4qa₃*qa₄ - (4qa₁*qa₂)) - (v₂*(4qa₁*qa₃ + 4qa₂*qa₄)))) - (v₁*(-qb₂*(4qa₁*qa₃ + 4qa₂*qa₄) - (qb₃*(4qa₃*qa₄ - (4qa₁*qa₂))) - (qb₄*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2)))))) - (v₃*(qb₁*(4qa₃*qa₄ - (4qa₁*qa₂)) + qb₂*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))) - (qb₄*(4qa₁*qa₃ + 4qa₂*qa₄)))))
    dG[4, 5] = λ₁*(qb₁*(v₂*(-4qa₁*qa₄ - (4qa₂*qa₃)) - (v₁*(2(qa₃^2) + 2(qa₄^2) - (2(qa₁^2)) - (2(qa₂^2)))) - (v₃*(4qa₂*qa₄ - (4qa₁*qa₃)))) + qb₄*(-v₁*(-4qa₁*qa₄ - (4qa₂*qa₃)) - (v₂*(2(qa₃^2) + 2(qa₄^2) - (2(qa₁^2)) - (2(qa₂^2))))) - (qb₂*(v₂*(4qa₂*qa₄ - (4qa₁*qa₃)) + v₃*(-4qa₁*qa₄ - (4qa₂*qa₃)))) - (qb₃*(v₁*(4qa₂*qa₄ - (4qa₁*qa₃)) - (v₃*(2(qa₃^2) + 2(qa₄^2) - (2(qa₁^2)) - (2(qa₂^2)))))) - (v₁*(qb₁*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))) + qb₄*(4qa₁*qa₄ + 4qa₂*qa₃) - (qb₃*(4qa₂*qa₄ - (4qa₁*qa₃))))) - (v₂*(qb₁*(4qa₁*qa₄ + 4qa₂*qa₃) + qb₂*(4qa₂*qa₄ - (4qa₁*qa₃)) - (qb₄*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2)))))) - (v₃*(qb₁*(4qa₂*qa₄ - (4qa₁*qa₃)) + qb₃*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))) - (qb₂*(4qa₁*qa₄ + 4qa₂*qa₃))))) + λ₂*(qb₁*(v₂*(2(qa₂^2) + 2(qa₄^2) - (2(qa₁^2)) - (2(qa₃^2))) - (v₁*(4qa₁*qa₄ - (4qa₂*qa₃))) - (v₃*(4qa₁*qa₂ + 4qa₃*qa₄))) + qb₄*(-v₁*(2(qa₂^2) + 2(qa₄^2) - (2(qa₁^2)) - (2(qa₃^2))) - (v₂*(4qa₁*qa₄ - (4qa₂*qa₃)))) - (qb₂*(v₂*(4qa₁*qa₂ + 4qa₃*qa₄) + v₃*(2(qa₂^2) + 2(qa₄^2) - (2(qa₁^2)) - (2(qa₃^2))))) - (qb₃*(v₁*(4qa₁*qa₂ + 4qa₃*qa₄) - (v₃*(4qa₁*qa₄ - (4qa₂*qa₃))))) - (v₁*(qb₁*(4qa₂*qa₃ - (4qa₁*qa₄)) + qb₄*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2))) - (qb₃*(4qa₁*qa₂ + 4qa₃*qa₄)))) - (v₂*(qb₁*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2))) + qb₂*(4qa₁*qa₂ + 4qa₃*qa₄) - (qb₄*(4qa₂*qa₃ - (4qa₁*qa₄))))) - (v₃*(qb₁*(4qa₁*qa₂ + 4qa₃*qa₄) + qb₃*(4qa₂*qa₃ - (4qa₁*qa₄)) - (qb₂*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2))))))) + λ₃*(qb₁*(v₂*(4qa₁*qa₂ - (4qa₃*qa₄)) - (v₁*(-4qa₁*qa₃ - (4qa₂*qa₄))) - (v₃*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))))) + qb₄*(-v₁*(4qa₁*qa₂ - (4qa₃*qa₄)) - (v₂*(-4qa₁*qa₃ - (4qa₂*qa₄)))) - (qb₂*(v₂*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))) + v₃*(4qa₁*qa₂ - (4qa₃*qa₄)))) - (qb₃*(v₁*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))) - (v₃*(-4qa₁*qa₃ - (4qa₂*qa₄))))) - (v₁*(qb₁*(4qa₁*qa₃ + 4qa₂*qa₄) + qb₄*(4qa₃*qa₄ - (4qa₁*qa₂)) - (qb₃*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2)))))) - (v₂*(qb₁*(4qa₃*qa₄ - (4qa₁*qa₂)) + qb₂*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))) - (qb₄*(4qa₁*qa₃ + 4qa₂*qa₄)))) - (v₃*(qb₁*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))) + qb₃*(4qa₁*qa₃ + 4qa₂*qa₄) - (qb₂*(4qa₃*qa₄ - (4qa₁*qa₂))))))
    dG[4, 6] = λ₁*(qb₁*(v₂*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))) - (v₁*(-4qa₁*qa₄ - (4qa₂*qa₃)))) + qb₄*(v₃*(4qa₁*qa₃ - (4qa₂*qa₄)) - (v₁*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2)))) - (v₂*(-4qa₁*qa₄ - (4qa₂*qa₃)))) + v₂*(qb₁*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))) + qb₄*(4qa₁*qa₄ + 4qa₂*qa₃) - (qb₃*(4qa₂*qa₄ - (4qa₁*qa₃)))) + v₃*(-qb₂*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))) - (qb₃*(4qa₁*qa₄ + 4qa₂*qa₃)) - (qb₄*(4qa₂*qa₄ - (4qa₁*qa₃)))) - (qb₂*(v₁*(4qa₁*qa₃ - (4qa₂*qa₄)) + v₃*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))))) - (qb₃*(-v₂*(4qa₁*qa₃ - (4qa₂*qa₄)) - (v₃*(-4qa₁*qa₄ - (4qa₂*qa₃))))) - (v₁*(qb₁*(4qa₁*qa₄ + 4qa₂*qa₃) + qb₂*(4qa₂*qa₄ - (4qa₁*qa₃)) - (qb₄*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))))))) + λ₂*(qb₁*(v₂*(4qa₂*qa₃ - (4qa₁*qa₄)) - (v₁*(2(qa₂^2) + 2(qa₄^2) - (2(qa₁^2)) - (2(qa₃^2))))) + qb₄*(v₃*(-4qa₁*qa₂ - (4qa₃*qa₄)) - (v₁*(4qa₂*qa₃ - (4qa₁*qa₄))) - (v₂*(2(qa₂^2) + 2(qa₄^2) - (2(qa₁^2)) - (2(qa₃^2))))) + v₂*(qb₁*(4qa₂*qa₃ - (4qa₁*qa₄)) + qb₄*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2))) - (qb₃*(4qa₁*qa₂ + 4qa₃*qa₄))) + v₃*(-qb₂*(4qa₂*qa₃ - (4qa₁*qa₄)) - (qb₃*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2)))) - (qb₄*(4qa₁*qa₂ + 4qa₃*qa₄))) - (qb₂*(v₁*(-4qa₁*qa₂ - (4qa₃*qa₄)) + v₃*(4qa₂*qa₃ - (4qa₁*qa₄)))) - (qb₃*(-v₂*(-4qa₁*qa₂ - (4qa₃*qa₄)) - (v₃*(2(qa₂^2) + 2(qa₄^2) - (2(qa₁^2)) - (2(qa₃^2)))))) - (v₁*(qb₁*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2))) + qb₂*(4qa₁*qa₂ + 4qa₃*qa₄) - (qb₄*(4qa₂*qa₃ - (4qa₁*qa₄)))))) + λ₃*(qb₁*(v₂*(4qa₁*qa₃ + 4qa₂*qa₄) - (v₁*(4qa₁*qa₂ - (4qa₃*qa₄)))) + qb₄*(v₃*(2(qa₂^2) + 2(qa₃^2) - (2(qa₁^2)) - (2(qa₄^2))) - (v₁*(4qa₁*qa₃ + 4qa₂*qa₄)) - (v₂*(4qa₁*qa₂ - (4qa₃*qa₄)))) + v₂*(qb₁*(4qa₁*qa₃ + 4qa₂*qa₄) + qb₄*(4qa₃*qa₄ - (4qa₁*qa₂)) - (qb₃*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))))) + v₃*(-qb₂*(4qa₁*qa₃ + 4qa₂*qa₄) - (qb₃*(4qa₃*qa₄ - (4qa₁*qa₂))) - (qb₄*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))))) - (qb₂*(v₁*(2(qa₂^2) + 2(qa₃^2) - (2(qa₁^2)) - (2(qa₄^2))) + v₃*(4qa₁*qa₃ + 4qa₂*qa₄))) - (qb₃*(-v₂*(2(qa₂^2) + 2(qa₃^2) - (2(qa₁^2)) - (2(qa₄^2))) - (v₃*(4qa₁*qa₂ - (4qa₃*qa₄))))) - (v₁*(qb₁*(4qa₃*qa₄ - (4qa₁*qa₂)) + qb₂*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))) - (qb₄*(4qa₁*qa₃ + 4qa₂*qa₄)))))
    dG[4, 7] = λ₁*(qb₁*(-v₁*(4qa₁*qa₃ - (4qa₂*qa₄)) - (v₃*(2(qa₃^2) + 2(qa₄^2) - (2(qa₁^2)) - (2(qa₂^2))))) + qb₄*(v₃*(4qa₁*qa₄ + 4qa₂*qa₃) - (v₂*(4qa₁*qa₃ - (4qa₂*qa₄)))) + v₃*(qb₁*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))) + qb₄*(4qa₁*qa₄ + 4qa₂*qa₃) - (qb₃*(4qa₂*qa₄ - (4qa₁*qa₃)))) - (qb₂*(v₁*(4qa₁*qa₄ + 4qa₂*qa₃) + v₂*(2(qa₃^2) + 2(qa₄^2) - (2(qa₁^2)) - (2(qa₂^2))))) - (qb₃*(v₁*(2(qa₃^2) + 2(qa₄^2) - (2(qa₁^2)) - (2(qa₂^2))) - (v₂*(4qa₁*qa₄ + 4qa₂*qa₃)) - (v₃*(4qa₁*qa₃ - (4qa₂*qa₄))))) - (v₁*(qb₁*(4qa₂*qa₄ - (4qa₁*qa₃)) + qb₃*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))) - (qb₂*(4qa₁*qa₄ + 4qa₂*qa₃)))) - (v₂*(-qb₂*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))) - (qb₃*(4qa₁*qa₄ + 4qa₂*qa₃)) - (qb₄*(4qa₂*qa₄ - (4qa₁*qa₃)))))) + λ₂*(qb₁*(-v₁*(-4qa₁*qa₂ - (4qa₃*qa₄)) - (v₃*(4qa₁*qa₄ - (4qa₂*qa₃)))) + qb₄*(v₃*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2))) - (v₂*(-4qa₁*qa₂ - (4qa₃*qa₄)))) + v₃*(qb₁*(4qa₂*qa₃ - (4qa₁*qa₄)) + qb₄*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2))) - (qb₃*(4qa₁*qa₂ + 4qa₃*qa₄))) - (qb₂*(v₁*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2))) + v₂*(4qa₁*qa₄ - (4qa₂*qa₃)))) - (qb₃*(v₁*(4qa₁*qa₄ - (4qa₂*qa₃)) - (v₂*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2)))) - (v₃*(-4qa₁*qa₂ - (4qa₃*qa₄))))) - (v₁*(qb₁*(4qa₁*qa₂ + 4qa₃*qa₄) + qb₃*(4qa₂*qa₃ - (4qa₁*qa₄)) - (qb₂*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2)))))) - (v₂*(-qb₂*(4qa₂*qa₃ - (4qa₁*qa₄)) - (qb₃*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2)))) - (qb₄*(4qa₁*qa₂ + 4qa₃*qa₄))))) + λ₃*(qb₁*(-v₁*(2(qa₂^2) + 2(qa₃^2) - (2(qa₁^2)) - (2(qa₄^2))) - (v₃*(-4qa₁*qa₃ - (4qa₂*qa₄)))) + qb₄*(v₃*(4qa₃*qa₄ - (4qa₁*qa₂)) - (v₂*(2(qa₂^2) + 2(qa₃^2) - (2(qa₁^2)) - (2(qa₄^2))))) + v₃*(qb₁*(4qa₁*qa₃ + 4qa₂*qa₄) + qb₄*(4qa₃*qa₄ - (4qa₁*qa₂)) - (qb₃*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))))) - (qb₂*(v₁*(4qa₃*qa₄ - (4qa₁*qa₂)) + v₂*(-4qa₁*qa₃ - (4qa₂*qa₄)))) - (qb₃*(v₁*(-4qa₁*qa₃ - (4qa₂*qa₄)) - (v₂*(4qa₃*qa₄ - (4qa₁*qa₂))) - (v₃*(2(qa₂^2) + 2(qa₃^2) - (2(qa₁^2)) - (2(qa₄^2)))))) - (v₁*(qb₁*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))) + qb₃*(4qa₁*qa₃ + 4qa₂*qa₄) - (qb₂*(4qa₃*qa₄ - (4qa₁*qa₂))))) - (v₂*(-qb₂*(4qa₁*qa₃ + 4qa₂*qa₄) - (qb₃*(4qa₃*qa₄ - (4qa₁*qa₂))) - (qb₄*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2)))))))
    dG[5, 1] = 0
    dG[5, 2] = 0
    dG[5, 3] = 0
    dG[5, 4] = λ₁*(qb₁*(v₃*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))) - (v₁*(4qa₂*qa₄ - (4qa₁*qa₃)))) + qb₂*(v₁*(4qa₁*qa₄ + 4qa₂*qa₃) - (v₂*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))))) + v₃*(qb₁*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))) + qb₄*(4qa₁*qa₄ + 4qa₂*qa₃) - (qb₃*(4qa₂*qa₄ - (4qa₁*qa₃)))) - (qb₃*(v₁*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))) + v₂*(4qa₁*qa₄ + 4qa₂*qa₃) + v₃*(4qa₂*qa₄ - (4qa₁*qa₃)))) - (qb₄*(v₂*(4qa₂*qa₄ - (4qa₁*qa₃)) - (v₃*(4qa₁*qa₄ + 4qa₂*qa₃)))) - (v₁*(qb₁*(4qa₂*qa₄ - (4qa₁*qa₃)) + qb₃*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))) - (qb₂*(4qa₁*qa₄ + 4qa₂*qa₃)))) - (v₂*(-qb₂*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))) - (qb₃*(4qa₁*qa₄ + 4qa₂*qa₃)) - (qb₄*(4qa₂*qa₄ - (4qa₁*qa₃)))))) + λ₂*(qb₁*(v₃*(4qa₂*qa₃ - (4qa₁*qa₄)) - (v₁*(4qa₁*qa₂ + 4qa₃*qa₄))) + qb₂*(v₁*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2))) - (v₂*(4qa₂*qa₃ - (4qa₁*qa₄)))) + v₃*(qb₁*(4qa₂*qa₃ - (4qa₁*qa₄)) + qb₄*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2))) - (qb₃*(4qa₁*qa₂ + 4qa₃*qa₄))) - (qb₃*(v₁*(4qa₂*qa₃ - (4qa₁*qa₄)) + v₂*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2))) + v₃*(4qa₁*qa₂ + 4qa₃*qa₄))) - (qb₄*(v₂*(4qa₁*qa₂ + 4qa₃*qa₄) - (v₃*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2)))))) - (v₁*(qb₁*(4qa₁*qa₂ + 4qa₃*qa₄) + qb₃*(4qa₂*qa₃ - (4qa₁*qa₄)) - (qb₂*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2)))))) - (v₂*(-qb₂*(4qa₂*qa₃ - (4qa₁*qa₄)) - (qb₃*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2)))) - (qb₄*(4qa₁*qa₂ + 4qa₃*qa₄))))) + λ₃*(qb₁*(v₃*(4qa₁*qa₃ + 4qa₂*qa₄) - (v₁*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))))) + qb₂*(v₁*(4qa₃*qa₄ - (4qa₁*qa₂)) - (v₂*(4qa₁*qa₃ + 4qa₂*qa₄))) + v₃*(qb₁*(4qa₁*qa₃ + 4qa₂*qa₄) + qb₄*(4qa₃*qa₄ - (4qa₁*qa₂)) - (qb₃*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))))) - (qb₃*(v₁*(4qa₁*qa₃ + 4qa₂*qa₄) + v₂*(4qa₃*qa₄ - (4qa₁*qa₂)) + v₃*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))))) - (qb₄*(v₂*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))) - (v₃*(4qa₃*qa₄ - (4qa₁*qa₂))))) - (v₁*(qb₁*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))) + qb₃*(4qa₁*qa₃ + 4qa₂*qa₄) - (qb₂*(4qa₃*qa₄ - (4qa₁*qa₂))))) - (v₂*(-qb₂*(4qa₁*qa₃ + 4qa₂*qa₄) - (qb₃*(4qa₃*qa₄ - (4qa₁*qa₂))) - (qb₄*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2)))))))
    dG[5, 5] = λ₁*(qb₁*(-v₁*(-4qa₁*qa₄ - (4qa₂*qa₃)) - (v₂*(2(qa₃^2) + 2(qa₄^2) - (2(qa₁^2)) - (2(qa₂^2))))) + qb₂*(v₁*(4qa₂*qa₄ - (4qa₁*qa₃)) - (v₃*(2(qa₃^2) + 2(qa₄^2) - (2(qa₁^2)) - (2(qa₂^2))))) + v₁*(qb₁*(4qa₁*qa₄ + 4qa₂*qa₃) + qb₂*(4qa₂*qa₄ - (4qa₁*qa₃)) - (qb₄*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))))) - (qb₃*(v₂*(4qa₂*qa₄ - (4qa₁*qa₃)) + v₃*(-4qa₁*qa₄ - (4qa₂*qa₃)))) - (qb₄*(v₂*(-4qa₁*qa₄ - (4qa₂*qa₃)) - (v₁*(2(qa₃^2) + 2(qa₄^2) - (2(qa₁^2)) - (2(qa₂^2)))) - (v₃*(4qa₂*qa₄ - (4qa₁*qa₃))))) - (v₂*(qb₁*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))) + qb₄*(4qa₁*qa₄ + 4qa₂*qa₃) - (qb₃*(4qa₂*qa₄ - (4qa₁*qa₃))))) - (v₃*(-qb₂*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))) - (qb₃*(4qa₁*qa₄ + 4qa₂*qa₃)) - (qb₄*(4qa₂*qa₄ - (4qa₁*qa₃)))))) + λ₂*(qb₁*(-v₁*(2(qa₂^2) + 2(qa₄^2) - (2(qa₁^2)) - (2(qa₃^2))) - (v₂*(4qa₁*qa₄ - (4qa₂*qa₃)))) + qb₂*(v₁*(4qa₁*qa₂ + 4qa₃*qa₄) - (v₃*(4qa₁*qa₄ - (4qa₂*qa₃)))) + v₁*(qb₁*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2))) + qb₂*(4qa₁*qa₂ + 4qa₃*qa₄) - (qb₄*(4qa₂*qa₃ - (4qa₁*qa₄)))) - (qb₃*(v₂*(4qa₁*qa₂ + 4qa₃*qa₄) + v₃*(2(qa₂^2) + 2(qa₄^2) - (2(qa₁^2)) - (2(qa₃^2))))) - (qb₄*(v₂*(2(qa₂^2) + 2(qa₄^2) - (2(qa₁^2)) - (2(qa₃^2))) - (v₁*(4qa₁*qa₄ - (4qa₂*qa₃))) - (v₃*(4qa₁*qa₂ + 4qa₃*qa₄)))) - (v₂*(qb₁*(4qa₂*qa₃ - (4qa₁*qa₄)) + qb₄*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2))) - (qb₃*(4qa₁*qa₂ + 4qa₃*qa₄)))) - (v₃*(-qb₂*(4qa₂*qa₃ - (4qa₁*qa₄)) - (qb₃*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2)))) - (qb₄*(4qa₁*qa₂ + 4qa₃*qa₄))))) + λ₃*(qb₁*(-v₁*(4qa₁*qa₂ - (4qa₃*qa₄)) - (v₂*(-4qa₁*qa₃ - (4qa₂*qa₄)))) + qb₂*(v₁*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))) - (v₃*(-4qa₁*qa₃ - (4qa₂*qa₄)))) + v₁*(qb₁*(4qa₃*qa₄ - (4qa₁*qa₂)) + qb₂*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))) - (qb₄*(4qa₁*qa₃ + 4qa₂*qa₄))) - (qb₃*(v₂*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))) + v₃*(4qa₁*qa₂ - (4qa₃*qa₄)))) - (qb₄*(v₂*(4qa₁*qa₂ - (4qa₃*qa₄)) - (v₁*(-4qa₁*qa₃ - (4qa₂*qa₄))) - (v₃*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2)))))) - (v₂*(qb₁*(4qa₁*qa₃ + 4qa₂*qa₄) + qb₄*(4qa₃*qa₄ - (4qa₁*qa₂)) - (qb₃*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2)))))) - (v₃*(-qb₂*(4qa₁*qa₃ + 4qa₂*qa₄) - (qb₃*(4qa₃*qa₄ - (4qa₁*qa₂))) - (qb₄*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2)))))))
    dG[5, 6] = λ₁*(qb₁*(v₃*(4qa₁*qa₃ - (4qa₂*qa₄)) - (v₁*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2)))) - (v₂*(-4qa₁*qa₄ - (4qa₂*qa₃)))) + qb₂*(-v₂*(4qa₁*qa₃ - (4qa₂*qa₄)) - (v₃*(-4qa₁*qa₄ - (4qa₂*qa₃)))) - (qb₃*(v₁*(4qa₁*qa₃ - (4qa₂*qa₄)) + v₃*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))))) - (qb₄*(v₂*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))) - (v₁*(-4qa₁*qa₄ - (4qa₂*qa₃))))) - (v₁*(qb₁*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))) + qb₄*(4qa₁*qa₄ + 4qa₂*qa₃) - (qb₃*(4qa₂*qa₄ - (4qa₁*qa₃))))) - (v₂*(qb₁*(4qa₁*qa₄ + 4qa₂*qa₃) + qb₂*(4qa₂*qa₄ - (4qa₁*qa₃)) - (qb₄*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2)))))) - (v₃*(qb₁*(4qa₂*qa₄ - (4qa₁*qa₃)) + qb₃*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))) - (qb₂*(4qa₁*qa₄ + 4qa₂*qa₃))))) + λ₂*(qb₁*(v₃*(-4qa₁*qa₂ - (4qa₃*qa₄)) - (v₁*(4qa₂*qa₃ - (4qa₁*qa₄))) - (v₂*(2(qa₂^2) + 2(qa₄^2) - (2(qa₁^2)) - (2(qa₃^2))))) + qb₂*(-v₂*(-4qa₁*qa₂ - (4qa₃*qa₄)) - (v₃*(2(qa₂^2) + 2(qa₄^2) - (2(qa₁^2)) - (2(qa₃^2))))) - (qb₃*(v₁*(-4qa₁*qa₂ - (4qa₃*qa₄)) + v₃*(4qa₂*qa₃ - (4qa₁*qa₄)))) - (qb₄*(v₂*(4qa₂*qa₃ - (4qa₁*qa₄)) - (v₁*(2(qa₂^2) + 2(qa₄^2) - (2(qa₁^2)) - (2(qa₃^2)))))) - (v₁*(qb₁*(4qa₂*qa₃ - (4qa₁*qa₄)) + qb₄*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2))) - (qb₃*(4qa₁*qa₂ + 4qa₃*qa₄)))) - (v₂*(qb₁*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2))) + qb₂*(4qa₁*qa₂ + 4qa₃*qa₄) - (qb₄*(4qa₂*qa₃ - (4qa₁*qa₄))))) - (v₃*(qb₁*(4qa₁*qa₂ + 4qa₃*qa₄) + qb₃*(4qa₂*qa₃ - (4qa₁*qa₄)) - (qb₂*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2))))))) + λ₃*(qb₁*(v₃*(2(qa₂^2) + 2(qa₃^2) - (2(qa₁^2)) - (2(qa₄^2))) - (v₁*(4qa₁*qa₃ + 4qa₂*qa₄)) - (v₂*(4qa₁*qa₂ - (4qa₃*qa₄)))) + qb₂*(-v₂*(2(qa₂^2) + 2(qa₃^2) - (2(qa₁^2)) - (2(qa₄^2))) - (v₃*(4qa₁*qa₂ - (4qa₃*qa₄)))) - (qb₃*(v₁*(2(qa₂^2) + 2(qa₃^2) - (2(qa₁^2)) - (2(qa₄^2))) + v₃*(4qa₁*qa₃ + 4qa₂*qa₄))) - (qb₄*(v₂*(4qa₁*qa₃ + 4qa₂*qa₄) - (v₁*(4qa₁*qa₂ - (4qa₃*qa₄))))) - (v₁*(qb₁*(4qa₁*qa₃ + 4qa₂*qa₄) + qb₄*(4qa₃*qa₄ - (4qa₁*qa₂)) - (qb₃*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2)))))) - (v₂*(qb₁*(4qa₃*qa₄ - (4qa₁*qa₂)) + qb₂*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))) - (qb₄*(4qa₁*qa₃ + 4qa₂*qa₄)))) - (v₃*(qb₁*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))) + qb₃*(4qa₁*qa₃ + 4qa₂*qa₄) - (qb₂*(4qa₃*qa₄ - (4qa₁*qa₂))))))
    dG[5, 7] = λ₁*(qb₁*(v₃*(4qa₁*qa₄ + 4qa₂*qa₃) - (v₂*(4qa₁*qa₃ - (4qa₂*qa₄)))) + qb₂*(v₁*(2(qa₃^2) + 2(qa₄^2) - (2(qa₁^2)) - (2(qa₂^2))) - (v₂*(4qa₁*qa₄ + 4qa₂*qa₃)) - (v₃*(4qa₁*qa₃ - (4qa₂*qa₄)))) + v₁*(-qb₂*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))) - (qb₃*(4qa₁*qa₄ + 4qa₂*qa₃)) - (qb₄*(4qa₂*qa₄ - (4qa₁*qa₃)))) + v₃*(qb₁*(4qa₁*qa₄ + 4qa₂*qa₃) + qb₂*(4qa₂*qa₄ - (4qa₁*qa₃)) - (qb₄*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))))) - (qb₃*(v₁*(4qa₁*qa₄ + 4qa₂*qa₃) + v₂*(2(qa₃^2) + 2(qa₄^2) - (2(qa₁^2)) - (2(qa₂^2))))) - (qb₄*(-v₁*(4qa₁*qa₃ - (4qa₂*qa₄)) - (v₃*(2(qa₃^2) + 2(qa₄^2) - (2(qa₁^2)) - (2(qa₂^2)))))) - (v₂*(qb₁*(4qa₂*qa₄ - (4qa₁*qa₃)) + qb₃*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))) - (qb₂*(4qa₁*qa₄ + 4qa₂*qa₃))))) + λ₂*(qb₁*(v₃*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2))) - (v₂*(-4qa₁*qa₂ - (4qa₃*qa₄)))) + qb₂*(v₁*(4qa₁*qa₄ - (4qa₂*qa₃)) - (v₂*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2)))) - (v₃*(-4qa₁*qa₂ - (4qa₃*qa₄)))) + v₁*(-qb₂*(4qa₂*qa₃ - (4qa₁*qa₄)) - (qb₃*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2)))) - (qb₄*(4qa₁*qa₂ + 4qa₃*qa₄))) + v₃*(qb₁*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2))) + qb₂*(4qa₁*qa₂ + 4qa₃*qa₄) - (qb₄*(4qa₂*qa₃ - (4qa₁*qa₄)))) - (qb₃*(v₁*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2))) + v₂*(4qa₁*qa₄ - (4qa₂*qa₃)))) - (qb₄*(-v₁*(-4qa₁*qa₂ - (4qa₃*qa₄)) - (v₃*(4qa₁*qa₄ - (4qa₂*qa₃))))) - (v₂*(qb₁*(4qa₁*qa₂ + 4qa₃*qa₄) + qb₃*(4qa₂*qa₃ - (4qa₁*qa₄)) - (qb₂*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2))))))) + λ₃*(qb₁*(v₃*(4qa₃*qa₄ - (4qa₁*qa₂)) - (v₂*(2(qa₂^2) + 2(qa₃^2) - (2(qa₁^2)) - (2(qa₄^2))))) + qb₂*(v₁*(-4qa₁*qa₃ - (4qa₂*qa₄)) - (v₂*(4qa₃*qa₄ - (4qa₁*qa₂))) - (v₃*(2(qa₂^2) + 2(qa₃^2) - (2(qa₁^2)) - (2(qa₄^2))))) + v₁*(-qb₂*(4qa₁*qa₃ + 4qa₂*qa₄) - (qb₃*(4qa₃*qa₄ - (4qa₁*qa₂))) - (qb₄*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))))) + v₃*(qb₁*(4qa₃*qa₄ - (4qa₁*qa₂)) + qb₂*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))) - (qb₄*(4qa₁*qa₃ + 4qa₂*qa₄))) - (qb₃*(v₁*(4qa₃*qa₄ - (4qa₁*qa₂)) + v₂*(-4qa₁*qa₃ - (4qa₂*qa₄)))) - (qb₄*(-v₁*(2(qa₂^2) + 2(qa₃^2) - (2(qa₁^2)) - (2(qa₄^2))) - (v₃*(-4qa₁*qa₃ - (4qa₂*qa₄))))) - (v₂*(qb₁*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))) + qb₃*(4qa₁*qa₃ + 4qa₂*qa₄) - (qb₂*(4qa₃*qa₄ - (4qa₁*qa₂))))))
    dG[6, 1] = 0
    dG[6, 2] = 0
    dG[6, 3] = 0
    dG[6, 4] = λ₁*(qb₁*(v₁*(4qa₁*qa₄ + 4qa₂*qa₃) - (v₂*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))))) + qb₃*(v₂*(4qa₂*qa₄ - (4qa₁*qa₃)) - (v₃*(4qa₁*qa₄ + 4qa₂*qa₃))) + v₁*(qb₁*(4qa₁*qa₄ + 4qa₂*qa₃) + qb₂*(4qa₂*qa₄ - (4qa₁*qa₃)) - (qb₄*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))))) - (qb₂*(v₃*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))) - (v₁*(4qa₂*qa₄ - (4qa₁*qa₃))))) - (qb₄*(v₁*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))) + v₂*(4qa₁*qa₄ + 4qa₂*qa₃) + v₃*(4qa₂*qa₄ - (4qa₁*qa₃)))) - (v₂*(qb₁*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))) + qb₄*(4qa₁*qa₄ + 4qa₂*qa₃) - (qb₃*(4qa₂*qa₄ - (4qa₁*qa₃))))) - (v₃*(-qb₂*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))) - (qb₃*(4qa₁*qa₄ + 4qa₂*qa₃)) - (qb₄*(4qa₂*qa₄ - (4qa₁*qa₃)))))) + λ₂*(qb₁*(v₁*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2))) - (v₂*(4qa₂*qa₃ - (4qa₁*qa₄)))) + qb₃*(v₂*(4qa₁*qa₂ + 4qa₃*qa₄) - (v₃*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2))))) + v₁*(qb₁*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2))) + qb₂*(4qa₁*qa₂ + 4qa₃*qa₄) - (qb₄*(4qa₂*qa₃ - (4qa₁*qa₄)))) - (qb₂*(v₃*(4qa₂*qa₃ - (4qa₁*qa₄)) - (v₁*(4qa₁*qa₂ + 4qa₃*qa₄)))) - (qb₄*(v₁*(4qa₂*qa₃ - (4qa₁*qa₄)) + v₂*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2))) + v₃*(4qa₁*qa₂ + 4qa₃*qa₄))) - (v₂*(qb₁*(4qa₂*qa₃ - (4qa₁*qa₄)) + qb₄*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2))) - (qb₃*(4qa₁*qa₂ + 4qa₃*qa₄)))) - (v₃*(-qb₂*(4qa₂*qa₃ - (4qa₁*qa₄)) - (qb₃*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2)))) - (qb₄*(4qa₁*qa₂ + 4qa₃*qa₄))))) + λ₃*(qb₁*(v₁*(4qa₃*qa₄ - (4qa₁*qa₂)) - (v₂*(4qa₁*qa₃ + 4qa₂*qa₄))) + qb₃*(v₂*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))) - (v₃*(4qa₃*qa₄ - (4qa₁*qa₂)))) + v₁*(qb₁*(4qa₃*qa₄ - (4qa₁*qa₂)) + qb₂*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))) - (qb₄*(4qa₁*qa₃ + 4qa₂*qa₄))) - (qb₂*(v₃*(4qa₁*qa₃ + 4qa₂*qa₄) - (v₁*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2)))))) - (qb₄*(v₁*(4qa₁*qa₃ + 4qa₂*qa₄) + v₂*(4qa₃*qa₄ - (4qa₁*qa₂)) + v₃*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))))) - (v₂*(qb₁*(4qa₁*qa₃ + 4qa₂*qa₄) + qb₄*(4qa₃*qa₄ - (4qa₁*qa₂)) - (qb₃*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2)))))) - (v₃*(-qb₂*(4qa₁*qa₃ + 4qa₂*qa₄) - (qb₃*(4qa₃*qa₄ - (4qa₁*qa₂))) - (qb₄*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2)))))))
    dG[6, 5] = λ₁*(qb₁*(v₁*(4qa₂*qa₄ - (4qa₁*qa₃)) - (v₃*(2(qa₃^2) + 2(qa₄^2) - (2(qa₁^2)) - (2(qa₂^2))))) + qb₃*(v₂*(-4qa₁*qa₄ - (4qa₂*qa₃)) - (v₁*(2(qa₃^2) + 2(qa₄^2) - (2(qa₁^2)) - (2(qa₂^2)))) - (v₃*(4qa₂*qa₄ - (4qa₁*qa₃)))) + v₁*(qb₁*(4qa₂*qa₄ - (4qa₁*qa₃)) + qb₃*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))) - (qb₂*(4qa₁*qa₄ + 4qa₂*qa₃))) + v₂*(-qb₂*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))) - (qb₃*(4qa₁*qa₄ + 4qa₂*qa₃)) - (qb₄*(4qa₂*qa₄ - (4qa₁*qa₃)))) - (qb₂*(-v₁*(-4qa₁*qa₄ - (4qa₂*qa₃)) - (v₂*(2(qa₃^2) + 2(qa₄^2) - (2(qa₁^2)) - (2(qa₂^2)))))) - (qb₄*(v₂*(4qa₂*qa₄ - (4qa₁*qa₃)) + v₃*(-4qa₁*qa₄ - (4qa₂*qa₃)))) - (v₃*(qb₁*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))) + qb₄*(4qa₁*qa₄ + 4qa₂*qa₃) - (qb₃*(4qa₂*qa₄ - (4qa₁*qa₃)))))) + λ₂*(qb₁*(v₁*(4qa₁*qa₂ + 4qa₃*qa₄) - (v₃*(4qa₁*qa₄ - (4qa₂*qa₃)))) + qb₃*(v₂*(2(qa₂^2) + 2(qa₄^2) - (2(qa₁^2)) - (2(qa₃^2))) - (v₁*(4qa₁*qa₄ - (4qa₂*qa₃))) - (v₃*(4qa₁*qa₂ + 4qa₃*qa₄))) + v₁*(qb₁*(4qa₁*qa₂ + 4qa₃*qa₄) + qb₃*(4qa₂*qa₃ - (4qa₁*qa₄)) - (qb₂*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2))))) + v₂*(-qb₂*(4qa₂*qa₃ - (4qa₁*qa₄)) - (qb₃*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2)))) - (qb₄*(4qa₁*qa₂ + 4qa₃*qa₄))) - (qb₂*(-v₁*(2(qa₂^2) + 2(qa₄^2) - (2(qa₁^2)) - (2(qa₃^2))) - (v₂*(4qa₁*qa₄ - (4qa₂*qa₃))))) - (qb₄*(v₂*(4qa₁*qa₂ + 4qa₃*qa₄) + v₃*(2(qa₂^2) + 2(qa₄^2) - (2(qa₁^2)) - (2(qa₃^2))))) - (v₃*(qb₁*(4qa₂*qa₃ - (4qa₁*qa₄)) + qb₄*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2))) - (qb₃*(4qa₁*qa₂ + 4qa₃*qa₄))))) + λ₃*(qb₁*(v₁*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))) - (v₃*(-4qa₁*qa₃ - (4qa₂*qa₄)))) + qb₃*(v₂*(4qa₁*qa₂ - (4qa₃*qa₄)) - (v₁*(-4qa₁*qa₃ - (4qa₂*qa₄))) - (v₃*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))))) + v₁*(qb₁*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))) + qb₃*(4qa₁*qa₃ + 4qa₂*qa₄) - (qb₂*(4qa₃*qa₄ - (4qa₁*qa₂)))) + v₂*(-qb₂*(4qa₁*qa₃ + 4qa₂*qa₄) - (qb₃*(4qa₃*qa₄ - (4qa₁*qa₂))) - (qb₄*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))))) - (qb₂*(-v₁*(4qa₁*qa₂ - (4qa₃*qa₄)) - (v₂*(-4qa₁*qa₃ - (4qa₂*qa₄))))) - (qb₄*(v₂*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))) + v₃*(4qa₁*qa₂ - (4qa₃*qa₄)))) - (v₃*(qb₁*(4qa₁*qa₃ + 4qa₂*qa₄) + qb₄*(4qa₃*qa₄ - (4qa₁*qa₂)) - (qb₃*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2)))))))
    dG[6, 6] = λ₁*(qb₁*(-v₂*(4qa₁*qa₃ - (4qa₂*qa₄)) - (v₃*(-4qa₁*qa₄ - (4qa₂*qa₃)))) + qb₃*(v₂*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))) - (v₁*(-4qa₁*qa₄ - (4qa₂*qa₃)))) + v₂*(qb₁*(4qa₂*qa₄ - (4qa₁*qa₃)) + qb₃*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))) - (qb₂*(4qa₁*qa₄ + 4qa₂*qa₃))) - (qb₂*(v₃*(4qa₁*qa₃ - (4qa₂*qa₄)) - (v₁*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2)))) - (v₂*(-4qa₁*qa₄ - (4qa₂*qa₃))))) - (qb₄*(v₁*(4qa₁*qa₃ - (4qa₂*qa₄)) + v₃*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))))) - (v₁*(-qb₂*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))) - (qb₃*(4qa₁*qa₄ + 4qa₂*qa₃)) - (qb₄*(4qa₂*qa₄ - (4qa₁*qa₃))))) - (v₃*(qb₁*(4qa₁*qa₄ + 4qa₂*qa₃) + qb₂*(4qa₂*qa₄ - (4qa₁*qa₃)) - (qb₄*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))))))) + λ₂*(qb₁*(-v₂*(-4qa₁*qa₂ - (4qa₃*qa₄)) - (v₃*(2(qa₂^2) + 2(qa₄^2) - (2(qa₁^2)) - (2(qa₃^2))))) + qb₃*(v₂*(4qa₂*qa₃ - (4qa₁*qa₄)) - (v₁*(2(qa₂^2) + 2(qa₄^2) - (2(qa₁^2)) - (2(qa₃^2))))) + v₂*(qb₁*(4qa₁*qa₂ + 4qa₃*qa₄) + qb₃*(4qa₂*qa₃ - (4qa₁*qa₄)) - (qb₂*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2))))) - (qb₂*(v₃*(-4qa₁*qa₂ - (4qa₃*qa₄)) - (v₁*(4qa₂*qa₃ - (4qa₁*qa₄))) - (v₂*(2(qa₂^2) + 2(qa₄^2) - (2(qa₁^2)) - (2(qa₃^2)))))) - (qb₄*(v₁*(-4qa₁*qa₂ - (4qa₃*qa₄)) + v₃*(4qa₂*qa₃ - (4qa₁*qa₄)))) - (v₁*(-qb₂*(4qa₂*qa₃ - (4qa₁*qa₄)) - (qb₃*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2)))) - (qb₄*(4qa₁*qa₂ + 4qa₃*qa₄)))) - (v₃*(qb₁*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2))) + qb₂*(4qa₁*qa₂ + 4qa₃*qa₄) - (qb₄*(4qa₂*qa₃ - (4qa₁*qa₄)))))) + λ₃*(qb₁*(-v₂*(2(qa₂^2) + 2(qa₃^2) - (2(qa₁^2)) - (2(qa₄^2))) - (v₃*(4qa₁*qa₂ - (4qa₃*qa₄)))) + qb₃*(v₂*(4qa₁*qa₃ + 4qa₂*qa₄) - (v₁*(4qa₁*qa₂ - (4qa₃*qa₄)))) + v₂*(qb₁*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))) + qb₃*(4qa₁*qa₃ + 4qa₂*qa₄) - (qb₂*(4qa₃*qa₄ - (4qa₁*qa₂)))) - (qb₂*(v₃*(2(qa₂^2) + 2(qa₃^2) - (2(qa₁^2)) - (2(qa₄^2))) - (v₁*(4qa₁*qa₃ + 4qa₂*qa₄)) - (v₂*(4qa₁*qa₂ - (4qa₃*qa₄))))) - (qb₄*(v₁*(2(qa₂^2) + 2(qa₃^2) - (2(qa₁^2)) - (2(qa₄^2))) + v₃*(4qa₁*qa₃ + 4qa₂*qa₄))) - (v₁*(-qb₂*(4qa₁*qa₃ + 4qa₂*qa₄) - (qb₃*(4qa₃*qa₄ - (4qa₁*qa₂))) - (qb₄*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2)))))) - (v₃*(qb₁*(4qa₃*qa₄ - (4qa₁*qa₂)) + qb₂*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))) - (qb₄*(4qa₁*qa₃ + 4qa₂*qa₄)))))
    dG[6, 7] = λ₁*(qb₁*(v₁*(2(qa₃^2) + 2(qa₄^2) - (2(qa₁^2)) - (2(qa₂^2))) - (v₂*(4qa₁*qa₄ + 4qa₂*qa₃)) - (v₃*(4qa₁*qa₃ - (4qa₂*qa₄)))) + qb₃*(-v₁*(4qa₁*qa₃ - (4qa₂*qa₄)) - (v₃*(2(qa₃^2) + 2(qa₄^2) - (2(qa₁^2)) - (2(qa₂^2))))) - (qb₂*(v₃*(4qa₁*qa₄ + 4qa₂*qa₃) - (v₂*(4qa₁*qa₃ - (4qa₂*qa₄))))) - (qb₄*(v₁*(4qa₁*qa₄ + 4qa₂*qa₃) + v₂*(2(qa₃^2) + 2(qa₄^2) - (2(qa₁^2)) - (2(qa₂^2))))) - (v₁*(qb₁*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))) + qb₄*(4qa₁*qa₄ + 4qa₂*qa₃) - (qb₃*(4qa₂*qa₄ - (4qa₁*qa₃))))) - (v₂*(qb₁*(4qa₁*qa₄ + 4qa₂*qa₃) + qb₂*(4qa₂*qa₄ - (4qa₁*qa₃)) - (qb₄*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2)))))) - (v₃*(qb₁*(4qa₂*qa₄ - (4qa₁*qa₃)) + qb₃*(2(qa₁^2) + 2(qa₂^2) - (2(qa₃^2)) - (2(qa₄^2))) - (qb₂*(4qa₁*qa₄ + 4qa₂*qa₃))))) + λ₂*(qb₁*(v₁*(4qa₁*qa₄ - (4qa₂*qa₃)) - (v₂*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2)))) - (v₃*(-4qa₁*qa₂ - (4qa₃*qa₄)))) + qb₃*(-v₁*(-4qa₁*qa₂ - (4qa₃*qa₄)) - (v₃*(4qa₁*qa₄ - (4qa₂*qa₃)))) - (qb₂*(v₃*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2))) - (v₂*(-4qa₁*qa₂ - (4qa₃*qa₄))))) - (qb₄*(v₁*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2))) + v₂*(4qa₁*qa₄ - (4qa₂*qa₃)))) - (v₁*(qb₁*(4qa₂*qa₃ - (4qa₁*qa₄)) + qb₄*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2))) - (qb₃*(4qa₁*qa₂ + 4qa₃*qa₄)))) - (v₂*(qb₁*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2))) + qb₂*(4qa₁*qa₂ + 4qa₃*qa₄) - (qb₄*(4qa₂*qa₃ - (4qa₁*qa₄))))) - (v₃*(qb₁*(4qa₁*qa₂ + 4qa₃*qa₄) + qb₃*(4qa₂*qa₃ - (4qa₁*qa₄)) - (qb₂*(2(qa₁^2) + 2(qa₃^2) - (2(qa₂^2)) - (2(qa₄^2))))))) + λ₃*(qb₁*(v₁*(-4qa₁*qa₃ - (4qa₂*qa₄)) - (v₂*(4qa₃*qa₄ - (4qa₁*qa₂))) - (v₃*(2(qa₂^2) + 2(qa₃^2) - (2(qa₁^2)) - (2(qa₄^2))))) + qb₃*(-v₁*(2(qa₂^2) + 2(qa₃^2) - (2(qa₁^2)) - (2(qa₄^2))) - (v₃*(-4qa₁*qa₃ - (4qa₂*qa₄)))) - (qb₂*(v₃*(4qa₃*qa₄ - (4qa₁*qa₂)) - (v₂*(2(qa₂^2) + 2(qa₃^2) - (2(qa₁^2)) - (2(qa₄^2)))))) - (qb₄*(v₁*(4qa₃*qa₄ - (4qa₁*qa₂)) + v₂*(-4qa₁*qa₃ - (4qa₂*qa₄)))) - (v₁*(qb₁*(4qa₁*qa₃ + 4qa₂*qa₄) + qb₄*(4qa₃*qa₄ - (4qa₁*qa₂)) - (qb₃*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2)))))) - (v₂*(qb₁*(4qa₃*qa₄ - (4qa₁*qa₂)) + qb₂*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))) - (qb₄*(4qa₁*qa₃ + 4qa₂*qa₄)))) - (v₃*(qb₁*(2(qa₁^2) + 2(qa₄^2) - (2(qa₂^2)) - (2(qa₃^2))) + qb₃*(4qa₁*qa₃ + 4qa₂*qa₄) - (qb₂*(4qa₃*qa₄ - (4qa₁*qa₂))))))
    return dG
end

function _dGb(joint::Translational{T,N}, xb::AbstractVector, qb::UnitQuaternion, λ::AbstractVector) where {T,N}
    xb₁, xb₂, xb₃ = xb
    qb₁, qb₂, qb₃, qb₄ = [qb.w, qb.x, qb.y, qb.z]
    v₁, v₂, v₃ = joint.vertices[2]
    λ₁, λ₂, λ₃ = λ

    dG = zeros(6, 7)

    dG[1, 1] = 0
    dG[1, 2] = 0
    dG[1, 3] = 0
    dG[1, 4] = 0
    dG[1, 5] = 0
    dG[1, 6] = 0
    dG[1, 7] = 0
    dG[2, 1] = 0
    dG[2, 2] = 0
    dG[2, 3] = 0
    dG[2, 4] = 0
    dG[2, 5] = 0
    dG[2, 6] = 0
    dG[2, 7] = 0
    dG[3, 1] = 0
    dG[3, 2] = 0
    dG[3, 3] = 0
    dG[3, 4] = 0
    dG[3, 5] = 0
    dG[3, 6] = 0
    dG[3, 7] = 0
    dG[4, 1] = 0
    dG[4, 2] = 0
    dG[4, 3] = 0
    dG[4, 4] = λ₁*(4qb₃*v₂ + 4qb₄*v₃) + λ₂*(-4qb₁*v₃ - (4qb₂*v₂)) + λ₃*(4qb₁*v₂ - (4qb₂*v₃))
    dG[4, 5] = λ₁*(4qb₄*v₂ - (4qb₃*v₃)) + λ₂*(4qb₂*v₃ - (4qb₁*v₂)) + λ₃*(-4qb₁*v₃ - (4qb₂*v₂))
    dG[4, 6] = λ₁*(4qb₁*v₂ - (4qb₂*v₃)) + λ₂*(4qb₄*v₂ - (4qb₃*v₃)) + λ₃*(-4qb₃*v₂ - (4qb₄*v₃))
    dG[4, 7] = λ₁*(4qb₁*v₃ + 4qb₂*v₂) + λ₂*(4qb₃*v₂ + 4qb₄*v₃) + λ₃*(4qb₄*v₂ - (4qb₃*v₃))
    dG[5, 1] = 0
    dG[5, 2] = 0
    dG[5, 3] = 0
    dG[5, 4] = λ₁*(4qb₁*v₃ - (4qb₃*v₁)) + λ₂*(4qb₂*v₁ + 4qb₄*v₃) + λ₃*(-4qb₁*v₁ - (4qb₃*v₃))
    dG[5, 5] = λ₁*(4qb₂*v₃ - (4qb₄*v₁)) + λ₂*(4qb₁*v₁ + 4qb₃*v₃) + λ₃*(4qb₂*v₁ + 4qb₄*v₃)
    dG[5, 6] = λ₁*(-4qb₁*v₁ - (4qb₃*v₃)) + λ₂*(4qb₂*v₃ - (4qb₄*v₁)) + λ₃*(4qb₃*v₁ - (4qb₁*v₃))
    dG[5, 7] = λ₁*(-4qb₂*v₁ - (4qb₄*v₃)) + λ₂*(4qb₁*v₃ - (4qb₃*v₁)) + λ₃*(4qb₂*v₃ - (4qb₄*v₁))
    dG[6, 1] = 0
    dG[6, 2] = 0
    dG[6, 3] = 0
    dG[6, 4] = λ₁*(-4qb₁*v₂ - (4qb₄*v₁)) + λ₂*(4qb₁*v₁ - (4qb₄*v₂)) + λ₃*(4qb₂*v₁ + 4qb₃*v₂)
    dG[6, 5] = λ₁*(4qb₃*v₁ - (4qb₂*v₂)) + λ₂*(-4qb₂*v₁ - (4qb₃*v₂)) + λ₃*(4qb₁*v₁ - (4qb₄*v₂))
    dG[6, 6] = λ₁*(4qb₂*v₁ + 4qb₃*v₂) + λ₂*(4qb₃*v₁ - (4qb₂*v₂)) + λ₃*(4qb₁*v₂ + 4qb₄*v₁)
    dG[6, 7] = λ₁*(4qb₄*v₂ - (4qb₁*v₁)) + λ₂*(-4qb₁*v₂ - (4qb₄*v₁)) + λ₃*(4qb₃*v₁ - (4qb₂*v₂))
    return dG
end
