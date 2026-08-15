import os
import pandas as pd
import numpy as np
import psycopg2
from scipy import stats

# 1. Import the dot-env library
from dotenv import load_dotenv

# 2. Load the environment variables from .env file
load_dotenv()

# 3. Establish database connection (Update credentials to match Docker setup)
try:
    conn = psycopg2.connect(
        host="localhost",
        database=os.getenv('DB_NAME'),
        user=os.getenv('DB_USER'),
        password=os.getenv('DB_PASSWORD'),
        port=os.getenv('PORT', '5432')
    )
    print("🔌 Database connection successful!")
except Exception as e:
    print(f"❌ Connection failed: {e}")
    exit()

# 4. Extract analytical view data into Pandas
query = "SELECT location_name, total_units_sold, total_revenue FROM store_ranks_by_quantity_revenue;"
df = pd.read_sql_query(query, conn)
conn.close()


# 5. --- UPDATED: Robust Modified Z-Score Calculation ---
def modified_zscore(series):
    median = series.median()
    # scale='normal' multiplies MAD by ~1.4826 for consistency with std dev
    mad = stats.median_abs_deviation(series, scale='normal', nan_policy='omit')
    return (series - median) / mad.replace(0, 1) # Simple zero-division protection

df['revenue_zscore'] = modified_zscore(df['total_revenue'])
df['quantity_zscore'] = modified_zscore(df['total_units_sold'])

# 6. --- Segmentation logic updated for modified z-scores ---
def segment_by_z(z_score):
    if z_score < -0.5: return 'Low'
    elif z_score > 0.5: return 'High'
    else: return 'Medium'

df['revenue_tier'] = df['revenue_zscore'].apply(segment_by_z)
df['volume_tier'] = df['quantity_zscore'].apply(segment_by_z)

print(df[['location_name', 'revenue_zscore', 'revenue_tier']])
print(df[['location_name', 'quantity_zscore', 'volume_tier']])