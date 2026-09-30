#include "solver/z3_solver.h"

#include <chrono>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>

using symbfuzz::SolveStatus;
using symbfuzz::z3_solve;

static void require(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}

// An unsatisfiable pigeonhole formula takes far longer than a 1 ms budget.
// Keep the external test watchdog: the old helper never times this query out.
static std::string pigeonhole_query(int holes = 12) {
    std::ostringstream query;
    for (int pigeon = 0; pigeon <= holes; ++pigeon) {
        for (int hole = 0; hole < holes; ++hole)
            query << "(declare-const p" << pigeon << "h" << hole << " Bool)\n";
        query << "(assert (or";
        for (int hole = 0; hole < holes; ++hole)
            query << " p" << pigeon << "h" << hole;
        query << "))\n";
    }
    for (int hole = 0; hole < holes; ++hole)
        for (int first = 0; first <= holes; ++first)
            for (int second = first + 1; second <= holes; ++second)
                query << "(assert (not (and p" << first << "h" << hole
                      << " p" << second << "h" << hole << ")))\n";
    // Generated BMC scripts also request values after check-sat, including
    // when the solver returns unknown or unsat and no model is available.
    query << "(check-sat)\n(get-value (p0h0))\n";
    return query.str();
}

int main() {
    try {
        const std::string sat = "(declare-const x Bool)\n(assert x)\n"
                                "(check-sat)\n(get-value (x))\n";
        const auto witness = z3_solve(sat, 1000);
        require(witness.status == SolveStatus::Sat, "SAT query did not return SAT");
        require(witness.model_text.find("(x true)") != std::string::npos,
                "SAT witness values were lost");
        require(z3_solve(sat, 0).status == SolveStatus::Sat,
                "Zero-timeout query did not return SAT");

        const auto unsat = z3_solve("(declare-const x Bool)\n(assert x)\n"
                                   "(assert (not x))\n(check-sat)\n(get-value (x))\n", 1000);
        require(unsat.status == SolveStatus::Unsat,
                "Unavailable model after UNSAT changed the status");

        const auto start = std::chrono::steady_clock::now();
        const auto timed = z3_solve(pigeonhole_query(), 1);
        const auto elapsed = std::chrono::duration<double>(
            std::chrono::steady_clock::now() - start).count();
        require(timed.status == SolveStatus::Unknown, "Timed query did not return UNKNOWN");
        require(timed.model_text.empty(), "Timed query returned a witness");
        require(elapsed < 5.0, "The configured timeout did not bound the query");
        std::cout << "timeout: UNKNOWN in " << elapsed << " s\n";

        require(z3_solve(pigeonhole_query(7), 0).status == SolveStatus::Unsat,
                "A previous timeout leaked into an unlimited call");

        const auto limited = z3_solve("(set-option :reproducible-resource-limit 1)\n" +
                                     pigeonhole_query(), 1000);
        require(limited.status == SolveStatus::Unknown,
                "Resource-limit UNKNOWN was misclassified");
        require(limited.model_text.empty(), "Resource-limited query returned a witness");

        bool rejected = false;
        try {
            z3_solve("(assert missing_symbol)\n", 1000);
        } catch (const std::exception&) {
            rejected = true;
        }
        require(rejected, "Malformed script was silently accepted");
        std::cout << "PASS: SAT values, UNSAT, timeout UNKNOWN, resource UNKNOWN, "
                     "zero timeout, and malformed script\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL: " << error.what() << '\n';
        return 1;
    }
}
