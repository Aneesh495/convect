# Mathematical Formulation: Spatiotemporal Gaussian Processes and Kriging

## 1. Spatial Random Field Modeling

In spatiotemporal environmental monitoring, observations $Z(s)$ at geographic coordinates $s = (lat, lon)$ are treated as realizations of an intrinsically stationary spatial random process:

$$Z(s) = \mu(s) + \epsilon(s)$$

Where:
- $\mu(s)$ represents the spatial trend or drift surface (assumed constant $\mu$ in Ordinary Kriging).
- $\epsilon(s)$ is a zero-mean intrinsically stationary stochastic residual with spatial covariance $C(h) = \text{Cov}(Z(s), Z(s + h))$.

---

## 2. Empirical Semivariogram Estimation

The degree of spatial dependency across geographic lag distance $h$ is quantified by the empirical semivariogram $\hat{\gamma}(h)$:

$$\hat{\gamma}(h) = \frac{1}{2 |N(h)|} \sum_{(i,j) \in N(h)} (Z(s_i) - Z(s_j))^2$$

Where $N(h)$ denotes the set of sensor pairs separated by distance lag $h \pm \frac{\Delta h}{2}$.

### Theoretical Covariance Functions
Convect supports three parametric variogram kernels:

1. **Spherical Model**:
   $$\gamma(h) = \begin{cases}
   c_0 + c \left( \frac{3h}{2a} - \frac{h^3}{2a^3} \right) & 0 < h \le a \\
   c_0 + c & h > a
   \end{cases}$$

2. **Exponential Model**:
   $$\gamma(h) = c_0 + c \left( 1 - \exp\left( -\frac{3h}{a} \right) \right)$$

3. **Gaussian Model**:
   $$\gamma(h) = c_0 + c \left( 1 - \exp\left( -\frac{3h^2}{a^2} \right) \right)$$

Where $c_0$ is the nugget variance (measurement noise), $c$ is the partial sill, and $a$ is the practical correlation range.

---

## 3. Best Linear Unbiased Estimator (BLUE)

At an unmonitored target location $s_0$, Ordinary Kriging seeks a linear combination of nearby observations:

$$\hat{Z}(s_0) = \sum_{i=1}^k w_i Z(s_i)$$

Subject to the unbiasedness constraint:

$$\mathbb{E}[\hat{Z}(s_0) - Z(s_0)] = 0 \implies \sum_{i=1}^k w_i = 1$$

Minimizing the estimation error variance $\sigma_K^2 = \text{Var}(\hat{Z}(s_0) - Z(s_0))$ yields the Ordinary Kriging linear system:

$$\begin{bmatrix}
C(s_1, s_1) & C(s_1, s_2) & \cdots & C(s_1, s_k) & 1 \\
C(s_2, s_1) & C(s_2, s_2) & \cdots & C(s_2, s_k) & 1 \\
\vdots & \vdots & \ddots & \vdots & \vdots \\
C(s_k, s_1) & C(s_k, s_2) & \cdots & C(s_k, s_k) & 1 \\
1 & 1 & \cdots & 1 & 0
\end{bmatrix}
\begin{bmatrix}
w_1 \\
w_2 \\
\vdots \\
w_k \\
\mu
\end{bmatrix}
=
\begin{bmatrix}
C(s_1, s_0) \\
C(s_2, s_0) \\
\vdots \\
C(s_k, s_0) \\
1
\end{bmatrix}$$

---

## 4. Cholesky Factorization and Numerical Stability

Because the spatial covariance matrix $C_{k \times k}$ is symmetric positive semi-definite, Convect applies a diagonal Tikhonov regularization jitter $\epsilon \approx 10^{-8}$:

$$A = C + \epsilon I$$

Factorizing via Banachiewicz Cholesky decomposition $A = L L^T$ yields:
- $L_{j,j} = \sqrt{A_{j,j} - \sum_{k=0}^{j-1} L_{j,k}^2}$
- $L_{i,j} = \frac{1}{L_{j,j}} \left( A_{i,j} - \sum_{k=0}^{j-1} L_{i,k} L_{j,k} \right)$

Linear solve time per target query scales as $O(k^3)$ where $k \le 32$ nearest neighbors are retrieved in $O(\log N)$ time from the local Place R*-tree.
