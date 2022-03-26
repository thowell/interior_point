struct SolverAlt{T}
    problem::ProblemData{T} 
    methods::ProblemMethods 
    data::SolverData{T}
    variables::Vector{T} 
    candidate::Vector{T}
    indices::IndicesAlt
    dimensions::Dimensions
    linear_solver::LinearSolver
    central_path::Vector{T} 
    penalty::Vector{T}
    dual::Vector{T}
    options::Options{T}
end

function SolverAlt(methods, num_variables, num_equality, num_inequality; 
    options=Options())

    # problem data
    p_data = ProblemData(num_variables, num_equality, num_inequality)

    # solver data
    s_data = SolverData(num_variables, num_equality, num_inequality)

    # indices
    idx = IndicesAlt(num_variables, num_equality, num_inequality)

    # dimensions 
    dim = Dimensions(num_variables, num_equality, num_inequality)

    # variables 
    variables = zeros(dim.total) 
    candidate = zeros(dim.total)

    # interior-point 
    central_path = [1.0] 

    # augmented Lagrangian 
    penalty = [1.0] 
    dual = zeros(num_equality) 

    # linear solver TODO: constructor
    random_variables = randn(dim.total)
    problem!(p_data, methods, idx, random_variables,
        gradient=true,
        constraint=true,
        jacobian=true,
        hessian=true)
    matrix_symmetric!(s_data, p_data, idx, random_variables, central_path, penalty, dual)
    linear_solver = ldl_solver(s_data.matrix_symmetric)

    SolverAlt(
        p_data, 
        methods, 
        s_data,
        variables,
        candidate, 
        idx, 
        dim,
        linear_solver,
        central_path, 
        penalty, 
        dual,
        options,
    )
end



