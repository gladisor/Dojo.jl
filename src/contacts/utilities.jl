"""
    get_sdf(contact, x, q)

    returns the signed distance for a contact

    contact: ContactConstraint
    x: body position
    q: body orientation
"""
function get_sdf(contact::ContactConstraint{T,N,Nc,Cs}, x::AbstractVector{T},
    q::Quaternion{T}) where {T,N,Nc,Cs<:Contact{T,N}}
    model = contact.model
    return model.collision.contact_normal * (x + vector_rotate(model.collision.contact_origin, q)) - model.collision.contact_radius
end

function get_sdf(mechanism::Mechanism{T,Nn,Ne,Nb,Ni}, storage::Storage{T,N}) where {T,Nn,Ne,Nb,Ni,N}
    d = []
    for contact in mechanism.contacts
        ibody = get_body(mechanism, contact.parent_id).id - Ne
        push!(d, [get_sdf(contact, storage.x[ibody][i], storage.q[ibody][i]) for i = 1:N])
    end
    return d
end

"""
    contact_location(contact, x, q)

    location of contact point in world coordinates

    contact: ContactConstraint
    x: body position
    q: body orientation
"""
function contact_location(contact::ContactConstraint{T,N,Nc,Cs}, x::AbstractVector{T},
    q::Quaternion{T}) where {T,N,Nc,Cs<:Contact{T,N}}
    model = contact.model
    return x + vector_rotate(model.collision.contact_origin, q) - model.collision.contact_normal' * model.collision.contact_radius
end

function contact_location(contact::ContactConstraint{T,N,Nc,Cs},
    body::Body) where {T,N,Nc,Cs<:Contact{T,N}}
    x = body.state.x2
    q = body.state.q2
    return contact_location(contact, x, q)
end

function contact_location(mechanism::Mechanism, contact::ContactConstraint)
    body = mechanism.bodies[findfirst(x -> x.id == contact.parent_id, mechanism.bodies)]
    return contact_location(contact, body)
end

function contact_location(mechanism::Mechanism)
    return [contact_location(mechanism, contact) for contact in mechanism.contacts]
end

#="""
    string_location(contact, x, q)

    location of the attach point of the string in world coordinates

    collision: StringCollision
    x: body position
    q: body orientation
"""=#
function string_location(collision::StringCollision, x::AbstractVector{T},
    q::Quaternion{T}; relative::Symbol=:parent) where T
    origin = (relative == :parent) ? collision.origin_parent : collision.origin_child
    return x + vector_rotate(origin, q)
end

function string_location(collision::StringCollision, body::Body; relative::Symbol=:parent)
    x = body.state.x2
    q = body.state.q2
    return string_location(collision, x, q, relative=relative)
end

function string_location(mechanism::Mechanism, collision::StringCollision)
    pbody = get_body(mechanism, contact.parent_id)
    cbody = get_body(mechanism, contact.child_id)
    x_parent = string_location(collision, pbody, relative=:parent)
    x_child = string_location(collision, cbody, relative=:child)
    return x_parent, x_child
end
