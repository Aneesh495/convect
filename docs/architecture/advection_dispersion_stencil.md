# Numerical Analysis: Distributed 2D Finite-Difference Advection-Dispersion Stencil

## 1. Governing Partial Differential Equation

Environmental contaminant plumes, aerosol dispersion, and atmospheric heat transport follow the advection-diffusion-reaction partial differential equation (PDE):

$$\frac{\partial C}{\partial t} + u \frac{\partial C}{\partial x} + v \frac{\partial C}{\partial y} = D_x \frac{\partial^2 C}{\partial x^2} + D_y \frac{\partial^2 C}{\partial y^2} - k C + S(x, y, t)$$

Where:
- $C(x, y, t)$ is the scalar concentration field ($kg/m^3$ or $\mu g/m^3$).
- $(u, v)$ is the advective velocity vector field ($m/s$).
- $(D_x, D_y)$ represents the turbulent eddy diffusivity tensor ($m^2/s$).
- $k$ is the first-order degradation/deposition rate coefficient ($1/s$).
- $S(x, y, t)$ is the continuous or localized source injection rate from physical sensor feeds ($kg/(m^3 \cdot s)$).

---

## 2. Spatial Discretization & 5-Point Stencil

To evaluate the transport operator on a discrete geographic mesh with grid spacings $\Delta x$ and $\Delta y$, we employ a hybrid discretization:

### 2.1 First-Order Upwind Advection Discretization
To eliminate numerical oscillations (Gibbs phenomenon) and satisfy the maximum principle under advection-dominated regimes:

$$\left( u \frac{\partial C}{\partial x} \right)_{i,j} \approx \begin{cases}
u \frac{C_{i,j}^n - C_{i-1,j}^n}{\Delta x} & \text{if } u \ge 0 \\
u \frac{C_{i+1,j}^n - C_{i,j}^n}{\Delta x} & \text{if } u < 0
\end{cases}$$

$$\left( v \frac{\partial C}{\partial y} \right)_{i,j} \approx \begin{cases}
v \frac{C_{i,j}^n - C_{i,j-1}^n}{\Delta y} & \text{if } v \ge 0 \\
v \frac{C_{i,j+1}^n - C_{i,j}^n}{\Delta y} & \text{if } v < 0
\end{cases}$$

### 2.2 Second-Order Central Difference Diffusion
The isotropic Laplacian operator is approximated via standard second-order central differences:

$$\left( D_x \frac{\partial^2 C}{\partial x^2} \right)_{i,j} \approx D_x \frac{C_{i+1,j}^n - 2 C_{i,j}^n + C_{i-1,j}^n}{\Delta x^2}$$

$$\left( D_y \frac{\partial^2 C}{\partial y^2} \right)_{i,j} \approx D_y \frac{C_{i,j+1}^n - 2 C_{i,j}^n + C_{i,j-1}^n}{\Delta y^2}$$

---

## 3. Stability Bounds: Courant-Friedrichs-Lewy (CFL) Condition

Because the forward Euler explicit time integration scheme is conditionally stable, the simulation time step $\Delta t$ must strictly satisfy the combined advection-diffusion CFL constraint:

$$\Delta t \le \left( \frac{2 D_x}{\Delta x^2} + \frac{2 D_y}{\Delta y^2} + \frac{|u|}{\Delta x} + \frac{|v|}{\Delta y} + k \right)^{-1}$$

In Convect, the solver dynamically computes local cell physical distances using spherical Haversine projection and clamps $\Delta t$ to preserve numerical stability across extreme wind velocity bursts.

---

## 4. PGAS Halo Communication Topology

In X10's Partitioned Global Address Space architecture, the global 2D grid is spatially partitioned across Places along continuous Hilbert curves or rectangular subdomains:

```
+-------------------+-------------------+
| Place 0           | Place 1           |
| (Local Subdomain) | (Local Subdomain) |
|      | Ghost Cell | Ghost Cell |      |
|      v Exchanges  | Exchanges  v      |
+-------------------+-------------------+
| Place 2           | Place 3           |
| (Local Subdomain) | (Local Subdomain) |
+-------------------+-------------------+
```

### 4.1 Asynchronous Halo Boundary Exchange
At each discrete time step $t_n \to t_{n+1}$:
1. Each Place initiates asynchronous non-blocking memory copies to populate ghost boundaries on adjacent Places:
   ```x10
   finish {
       for (neighbor in adjacentPlaces) {
           async at(neighbor) {
               receiveHaloBoundary(localBoundaryBuffer);
           }
       }
   }
   ```
2. The outer `finish` block functions as a collective global barrier, guaranteeing all boundary conditions are synchronized before the 5-point stencil executes.
3. Interior cells $(i, j) \in [1..N-2]$ update independently in parallel, hiding inter-place network latency.
