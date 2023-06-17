pub const CsvConfig = struct {
    field_end_delimiter: u8 = ',',
    row_end_delimiter: u8 = '\n',
    quote_delimiter: u8 = '"',
    skip_first_row: bool = true,
};
