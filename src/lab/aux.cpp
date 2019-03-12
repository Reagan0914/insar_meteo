#include <lab/aux.hpp>

void Timer::reset()
{
    this->m_beg = clock_t::now();
}


double Timer::elapsed() const
{
    return std::chrono::duration_cast<second_t>(clock_t::now() - this->m_beg).count();
}


void Timer::report() const
{
    std::cout << "Elapsed time: " << this->elapsed() << " seconds.\n";
}


bool is_big_endian()
{
    short word = 0x4321;
    if ((*(char *)& word) != 0x21 )
    {
        return true;
    }
    else
    {
        return false;
    }
}
