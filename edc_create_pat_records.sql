with

    -- GET DATA FROM CURRENT ATE
    gather_current_ate_data as (
        select
            learner_account_id,
            current_ct_status_c,
            current_ct_phase_c,
            years_since_high_school_graduation_ate_c,

            -- POPULATE THIS EVERY YEAR
            'Spring' as term_to_create,
            '2024-25' as year_to_create,
            date(2025, 04, 01) as start_date_of_term_to_create,

            -- END MANUAL UPDATE
            ate_id as previous_academic_term_enrollment_c,
            ate_at_id as current_ate_at,
            'Undergraduate' as student_academic_level,
            learner_contact_id,
            ate_school_id,
            ct_coach_ate_c,
            ct_case_c,
            concurrent_school_enrolled_c,
            owner_id,
            ct_status_ate_c,
            ate_enrollment_status,
            major_category_c,  -- picklist
            major_c,  -- text
            second_major_category_c,  -- picklist
            second_major_c,  -- text
            minor_c  -- text
        from `prod_core.fct_edcloud_academic_term_enrollment`
        where
            current_at_c = true
            and (
                (
                    current_ct_status_c = 'Active'
                    and current_ct_phase_c = 'Post Secondary'
                )
                or (
                    current_ct_status_c = 'Inactive'
                    and current_ct_phase_c in ('Post Secondary', 'Alumni')
                    and years_since_high_school_graduation_ate_c < 5.99
                )
            )
    ),

    most_recent_credit as (
        select
            account_id,
            cumulative_credits_awarded_most_recent_pc
        from `data-studio-260217.prod_core.dim_scholar`
    ),

    join_credit as ( 
        select
            gather_current_ate_data.*,
            most_recent_credit.cumulative_credits_awarded_most_recent_pc
        from gather_current_ate_data
        left join most_recent_credit 
        on most_recent_credit.account_id = gather_current_ate_data.learner_account_id
    ),

    -- GET INFORMATION FROM GLOBAL ACADEMIC TERM
    current_at_data as (
        select
            at_id,
            at_name as current_at_name,
            academic_calendar_c as current_academic_calendar
        from `data-studio-260217.prod_staging.stg_edcloud__academic_term`
    ),

    join_current_at as (
        select
            join_credit.*,
            current_at_data.current_at_name,
            current_at_data.current_academic_calendar
        from join_credit
        left join
            current_at_data
            on current_at_data.at_id = join_credit.current_ate_at
    ),

    term_ids as (
        select
            at_id,
            academic_year_id,
            at_name,
            season,
            academic_calendar_c,
            date(at_start_date) as start_date,
            date(at_end_date) as exit_date
        from `data-studio-260217.prod_staging.stg_edcloud__academic_term`
    ),

    -- JOIN TERM DATA FOR NEXT TERM
    join_term_ids as (
        select
            join_current_at.*,
            term_ids.at_id,
            term_ids.academic_year_id,
            term_ids.at_name as at_name_to_create,
            term_ids.season as at_term_to_create,
            term_ids.start_date as enrollment_date,
            term_ids.exit_date
        from join_current_at
        inner join
            term_ids
            on join_current_at.start_date_of_term_to_create = term_ids.start_date
            and join_current_at.current_academic_calendar = term_ids.academic_calendar_c
    ),

    prep_data as (
        select
            at_name_to_create,
            learner_account_id,
            ct_status_ate_c,
            previous_academic_term_enrollment_c,
            at_id,
            academic_year_id,
            student_academic_level,
            ct_case_c,
            learner_contact_id,
            owner_id,
            enrollment_date,
            exit_date,
            concurrent_school_enrolled_c,

            -- following fields require scholar be active in order to be populated
            case
                when current_ct_status_c != 'Active' then null else major_category_c
            end as major_category_c,
            case
                when current_ct_status_c != 'Active' then null else major_c
            end as major_c,
            case
                when current_ct_status_c != 'Active'
                then null
                else second_major_category_c
            end as second_major_category_c,
            case
                when current_ct_status_c != 'Active' then null else second_major_c
            end as second_major_c,
            case
                when current_ct_status_c != 'Active' then null else minor_c
            end as minor_c,
            case
                when current_ct_status_c != 'Active'
                then null
                else ate_enrollment_status
            end as enrollment_status,
            case
                when current_ct_status_c != 'Active'
                then null
                else cumulative_credits_awarded_most_recent_pc
            end as cumulative_credits_awarded_all_terms_c,

            -- following fields null for alumni
            case
                when current_ct_phase_c = 'Alumni' then null else ate_school_id
            end as school_c,
            case
                when current_ct_phase_c = 'Alumni' then null else ct_coach_ate_c
            end as ct_coach_ate_c
        from join_term_ids
    )

select *
from  prep_data

    -- check_record_count as (
    --     select
    --         at_name_to_create,
    --         count(learner_account_id) as n_students,
    --         count(*) as n_records
    -- from prep_data
    -- group by 1
    -- )
    
    -- select * from check_record_count
