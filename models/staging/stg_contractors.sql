-- stg_contractors.sql
-- Staging model for raw contractors data.
-- Standardizes region, plan_type, and adds tenure calculation.
-- Grain: one row per contractor_id.

with source as (

    select * from {{ source('raw', 'contractors') }}

),

cleaned as (

    select
        -- primary key
        trim(contractor_id)                                     as contractor_id,

        -- attributes - strip whitespace, normalize case
        trim(name)                                              as contractor_name,
        lower(trim(region))                                     as region,
        lower(trim(plan_type))                                  as plan_type,

        -- timestamps
        cast(created_at as date)                                as created_date,

        -- derived: number of days the contractor has been on the platform
        datediff('day', cast(created_at as date), current_date) as days_on_platform,

        -- convenience tier flag ordered for easy filtering/sorting
        case lower(trim(plan_type))
            when 'starter'      then 1
            when 'professional' then 2
            when 'enterprise'   then 3
            else 0
        end                                                     as plan_tier

    from source
    where
        contractor_id is not null
        and name      is not null

)

select * from cleaned
