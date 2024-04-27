--For Analysts (Direct Querying):

--Employee Performance Analysis
--Top 5 best-performing employees based on performance amounts over the last year.
WITH RankedPerformance AS (
    SELECT employee_id,
        SUM(performance_amount) AS total_performance_amount,
        RANK() OVER (ORDER BY SUM(performance_amount) DESC) AS performance_rank
    FROM employee_performance
    WHERE performance_date >= current_date - INTERVAL '1 year'
    GROUP BY employee_id
)
SELECT employee_id, 
    total_performance_amount, 
    performance_rank
FROM RankedPerformance
WHERE performance_rank <= 10;

--Performance of employees from the 'sales' department with ranking based on total sales.
SELECT e.employee_id,
    e.department_name,
    SUM(t.transaction_amount) AS total_sales,
    RANK() OVER (ORDER BY SUM(t.transaction_amount) DESC) AS sales_rank
FROM transactions t
JOIN employees e ON t.employee_id = e.employee_id
WHERE e.department_name = 'Sales'
GROUP BY e.employee_id
ORDER BY total_sales DESC;

--Employees who have not achieved a minimum rating of at least 3 in the past six months.
SELECT e.employee_id, 
    e.first_name, 
    e.last_name
FROM employees e
WHERE NOT EXISTS (
    SELECT 1
    FROM employee_performance ep
    WHERE ep.employee_id = e.employee_id
      AND ep.employee_rating::INT >= 3
      AND ep.performance_date >= current_date - INTERVAL '6 months'
);

--Property Sales Insights
--Days on market before properties got sold.
WITH listed_properties AS (
    SELECT
        pl.property_id, 
        pl.listing_date, 
        MIN(t.transaction_date) AS sold_date
    FROM property_listings pl  
    JOIN transactions t ON pl.property_id = t.property_id  
    GROUP BY pl.property_id, pl.listing_date 
)
SELECT
    lp.property_id,  
    lp.listing_date, 
    lp.sold_date,
    lp.sold_date - lp.listing_date AS days_on_market
FROM listed_properties lp; 

--Property Status Automation
--Automatic update of property listing status when a property is sold.
CREATE OR REPLACE FUNCTION update_property_listing_status()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.terms = 'sold' THEN
        UPDATE property_listings
        SET status = 'sold'
        WHERE property_id = NEW.property_id;
    ELSIF OLD.terms = 'sold' AND NEW.terms <> 'sold' THEN
        UPDATE property_listings
        SET status = 'available'
        WHERE property_id = NEW.property_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_after_transaction_update
AFTER UPDATE ON transactions
FOR EACH ROW
EXECUTE FUNCTION update_property_listing_status();

--Market and Financial Analysis
--Quarterly sales and brokerage fees report for the current year.
SELECT
    EXTRACT(QUARTER FROM transaction_date) AS quarter,
    EXTRACT(YEAR FROM transaction_date) AS year,
    SUM(transaction_amount) AS total_sales,
    SUM(brokerage_fee) AS total_fees
FROM transactions
WHERE transaction_date BETWEEN DATE_TRUNC('year', CURRENT_DATE) AND CURRENT_DATE
GROUP BY quarter, year
ORDER BY year, quarter;

--Show key financial metrics from transactions, payroll, expenses, and net profit by office for financial analysis.
SELECT
    o.office_id,
    o.address,
    SUM(t.transaction_amount) AS revenue,
    SUM(p.salary_amount + p.bonus_amount) AS payroll_expenses,
    SUM(fr.amount) AS operational_expenses,
    SUM(t.transaction_amount) - (SUM(p.salary_amount + p.bonus_amount) + SUM(fr.amount)) AS net_profit
FROM offices o
LEFT JOIN employees e ON o.office_id = e.office_id
LEFT JOIN transactions t ON e.employee_id = t.employee_id
LEFT JOIN payroll p ON e.employee_id = p.employee_id
LEFT JOIN financial_records fr ON o.office_id = fr.office_id
GROUP BY o.office_id, 
    o.address;

--Determining the effectiveness of marketing campaigns by properties and their sales.
SELECT mc.campaign_id, mc.campaign_name, COUNT(*) AS number_of_properties, SUM(t.transaction_amount) AS total_revenue
FROM marketing_campaigns mc
JOIN property_listings pl ON mc.property_id = pl.property_id
LEFT JOIN transactions t ON pl.property_id = t.property_id
GROUP BY mc.campaign_id, 
    mc.campaign_name
ORDER BY total_revenue DESC; 
    
--For C-level Officers (Reports):

--Sales Performance and Budget Reporting

--Year-to-date sales performance report by each office.
WITH office_sales AS (
    SELECT o.office_id, o.city, 
    COUNT(t.transaction_id) AS total_sales, 
    SUM(t.transaction_amount) AS sales_volume
    FROM offices o
    LEFT JOIN employees e ON o.office_id = e.office_id
    LEFT JOIN transactions t ON e.employee_id = t.employee_id AND terms = 'sold'
    GROUP BY o.office_id
)
SELECT office_id, 
    city, 
    total_sales, 
    sales_volume
FROM office_sales
ORDER BY sales_volume DESC;

--Aggregate financial report showing income from sales and expenditure on marketing campaigns.
SELECT 'Income' AS type, 
    SUM(transaction_amount) AS amount
FROM transactions
WHERE transaction_date BETWEEN '2023-01-01' AND current_date
AND terms = 'sold'
UNION ALL
SELECT 'Marketing Expenditure' AS type, 
    SUM(budget) AS amount
FROM marketing_campaigns
WHERE start_date BETWEEN '2023-01-01' AND current_date;

--Employee Effectiveness and Market Performance
--Employee Specialization and Effectiveness Report.
SELECT e.employee_id, 
    e.first_name, 
    e.last_name, 
    s.specialization_area,
       COUNT(t.transaction_id) AS total_transactions,
       COALESCE(SUM(t.transaction_amount), 0) AS total_sales_volume 
FROM employees e
JOIN agent_specializations s ON e.employee_id = s.employee_id
LEFT JOIN transactions t ON e.employee_id = t.employee_id AND t.terms = 'sold'
GROUP BY e.employee_id, 
    s.specialization_area
ORDER BY total_sales_volume DESC, 
    total_transactions DESC;

--Report on the feedback ratings of employees by clients.
SELECT e.employee_id, 
    e.first_name, 
    e.last_name,
       ROUND(AVG(NULLIF(c.client_rating, 'Not Rated')::INT)) AS average_rating
FROM employees e
JOIN client_feedback c ON e.employee_id = c.employee_id
GROUP BY e.employee_id, 
    e.first_name, 
    e.last_name  
ORDER BY average_rating DESC;

--Operational Reports and Views
--Report of properties rented vs sold by each agent.
SELECT e.employee_id, 
    e.first_name, 
    e.last_name,
       COUNT(CASE WHEN pl.status = 'rented' THEN 1 END) AS properties_rented,
       COUNT(CASE WHEN t.terms = 'sold' THEN 1 END) AS properties_sold
FROM employees e
LEFT JOIN property_listings pl ON e.employee_id = pl.employee_id
LEFT JOIN transactions t ON pl.property_id = t.property_id
GROUP BY e.employee_id;

--Event details for open houses and viewing appointments.
SELECT e.event_id,
    e.event_type,
    e.event_date,
    e.start_time,
    e.end_time,
    pl.address AS property_address,
    pl.zip_code,
    COUNT(*) FILTER (WHERE e.attendees IS NOT NULL) AS number_of_attendees
FROM events e
JOIN property_listings pl ON e.property_id = pl.property_id
WHERE e.event_date >= CURRENT_DATE
GROUP BY e.event_id, 
    e.event_type, 
    e.event_date, 
    e.start_time, 
    e.end_time, 
    property_address, 
    pl.zip_code
ORDER BY e.event_date, e.start_time;

--Manager-Employee Office View for organizational structure insights.
CREATE VIEW manager_employee_view AS
SELECT m.employee_id AS manager_id, 
    e.employee_id AS employee_id,
    m.first_name AS manager_first_name, 
    m.last_name AS manager_last_name, 
    e.first_name AS employee_first_name, 
    e.last_name AS employee_last_name, 
    o.address AS office_address,
    o.city AS office_city
FROM employees e
JOIN manages man ON e.employee_id = man.employee_id
JOIN employees m ON man.manager_id = m.employee_id
JOIN offices o ON e.office_id = o.office_id;

